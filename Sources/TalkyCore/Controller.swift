import AppKit

/// The dictation state machine.
///
/// Main hotkey:
///   hold                     -> record while held, transcribe on release
///   short tap, short tap     -> hands-free; the next press stops and transcribes
///   short single tap         -> ignored (recording discarded)
/// Transform hotkey with text selected opens the picker: pick a pipe (click or digit),
/// or use the main hotkey to dictate an ad-hoc instruction.
/// Esc cancels whatever is in flight and is never swallowed.
@MainActor
public final class Controller: KeyMonitorDelegate {
    public enum Phase: Equatable { case idle, recording, processing, picker }
    enum Purpose: Equatable { case dictate, instruction(String) }

    /// Presses shorter than this count as taps, not holds.
    static let tapThreshold: TimeInterval = 0.25
    /// A different key within this time of pressing a modifier hotkey means it was a chord (fn+arrow), not dictation.
    static let chordGrace: TimeInterval = 0.6

    let configStore: ConfigStore
    let pipeStore: PipeStore
    let pill = PillController()
    let recorder = AudioRecorder()
    public let transcription = TranscriptionService()
    let llm = AnthropicClient()

    public private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    public var onPhaseChange: ((Phase) -> Void)?

    private var mode: RecordingMode = .hold
    private var purpose: Purpose = .dictate
    private var pickerSelection: String?
    private var sessionPipeId: String?
    private var mainDownAt: Date?
    private var downIsSecondTap = false
    private var lastTapUpAt: Date?
    private var ignoreNextMainUp = false
    private var recordingStartedAt = Date()
    private var work: Task<Void, Never>?
    private var tick: Timer?

    private var config: Config { configStore.config }

    public init(configStore: ConfigStore, pipeStore: PipeStore) {
        self.configStore = configStore
        self.pipeStore = pipeStore
        recorder.onLevel = { [weak self] level in self?.pill.model.level = level }

        let m = pill.model
        m.onSelectPipe = { [weak self] id in self?.selectSessionPipe(id) }
        m.onPickPipe = { [weak self] pipe in self?.runPipeOnSelection(pipe) }
        m.onSpeakInstruction = { [weak self] in self?.speakInstructionClicked() }
        m.onStop = { [weak self] in self?.finishRecording() }
        m.onClose = { [weak self] in self?.closePicker() }
    }

    // MARK: KeyMonitorDelegate

    public var hotkeysEnabled: Bool { config.enabled }

    public func mainHotkeyDown() {
        let now = Date()
        switch phase {
        case .recording where mode == .handsFree:
            ignoreNextMainUp = true
            finishRecording()
        case .idle, .picker:
            let window = config.handsFree.doubleTapWindowMs / 1000
            downIsSecondTap = lastTapUpAt.map { now.timeIntervalSince($0) < window } ?? false
            lastTapUpAt = nil
            mainDownAt = now
            if phase == .picker, let sel = pickerSelection {
                purpose = .instruction(sel)
            } else {
                purpose = .dictate
            }
            startRecording(mode: .hold)
        default:
            break
        }
    }

    public func mainHotkeyUp() {
        if ignoreNextMainUp {
            ignoreNextMainUp = false
            return
        }
        guard phase == .recording, mode == .hold, let down = mainDownAt else { return }
        mainDownAt = nil
        let held = Date().timeIntervalSince(down)
        if held >= Self.tapThreshold {
            finishRecording()
        } else if downIsSecondTap {
            enterHandsFree()
        } else {
            lastTapUpAt = Date()
            abortRecording()
        }
    }

    /// Pipes need Claude. Without an Anthropic key Talky pastes the raw transcript and hides them.
    private var pipesAvailable: Bool { config.llm.enabled && AnthropicClient.apiKey != nil }

    public func transformHotkeyFired() {
        switch phase {
        case .idle:
            guard AnthropicClient.apiKey != nil else {
                pill.flash("Add an Anthropic API key in Settings to transform text", seconds: 2.5)
                return
            }
            phase = .processing
            Task {
                let text = await TextIO.selectedText()
                guard phase == .processing else { return }
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    phase = .idle
                    pill.flash("Select some text first")
                    return
                }
                openPicker(selection: text)
            }
        case .picker:
            closePicker()
        default:
            break
        }
    }

    public func escapePressed() {
        switch phase {
        case .recording:
            stopTicking()
            recorder.cancel()
            pickerSelection = nil
            phase = .idle
            pill.hide()
        case .processing:
            work?.cancel()
            work = nil
            phase = .idle
            pill.flash("Cancelled", seconds: 0.8)
        case .picker:
            closePicker()
        case .idle:
            break
        }
    }

    public func digitPressed(_ n: Int) -> Bool {
        switch phase {
        case .recording where purpose == .dictate && config.showPipesInPill && pipesAvailable:
            if n == 0 { selectSessionPipe(nil); return true }
            guard n <= min(9, pipeStore.pipes.count) else { return false }
            selectSessionPipe(pipeStore.pipes[n - 1].id)
            return true
        case .picker:
            guard n >= 1, n <= min(9, pipeStore.pipes.count) else { return false }
            runPipeOnSelection(pipeStore.pipes[n - 1])
            return true
        default:
            return false
        }
    }

    public func otherKeyWhileHeld() {
        guard phase == .recording, mode == .hold, let down = mainDownAt,
              Date().timeIntervalSince(down) < Self.chordGrace else { return }
        mainDownAt = nil
        lastTapUpAt = nil
        ignoreNextMainUp = true
        abortRecording()
    }

    // MARK: Recording

    private func startRecording(mode: RecordingMode) {
        self.mode = mode
        if purpose == .dictate { sessionPipeId = pipesAvailable ? pipeStore.defaultPipeId : nil }
        do {
            try recorder.start()
        } catch {
            pill.flash(error.localizedDescription, isError: true, seconds: 3)
            phase = pickerSelection == nil ? .idle : .picker
            return
        }
        phase = .recording
        recordingStartedAt = Date()

        let m = pill.model
        m.mode = mode
        m.isInstruction = purpose != .dictate
        m.level = 0
        m.elapsed = 0
        m.remaining = nil
        m.pipes = pipeStore.pipes
        m.selectedPipeId = sessionPipeId
        m.showPipes = config.showPipesInPill && pipesAvailable
        pill.show(.recording)

        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
    }

    private func enterHandsFree() {
        mode = .handsFree
        pill.model.mode = .handsFree
        pill.relayout()
    }

    private func onTick() {
        guard phase == .recording else { return }
        let elapsed = Date().timeIntervalSince(recordingStartedAt)
        pill.model.elapsed = elapsed
        if mode == .handsFree {
            let remaining = config.handsFree.maxSeconds - elapsed
            if remaining <= 30 && pill.model.remaining == nil {
                pill.model.remaining = remaining
                pill.relayout()
            } else if pill.model.remaining != nil {
                pill.model.remaining = remaining
            }
            // A forgotten hands-free session stops itself and transcribes what it has.
            if remaining <= 0 { finishRecording() }
        }
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }

    /// Short single tap or a chord: drop the audio quietly.
    private func abortRecording() {
        stopTicking()
        recorder.cancel()
        if let sel = pickerSelection {
            openPicker(selection: sel)
        } else {
            phase = .idle
            pill.hide()
        }
    }

    private func selectSessionPipe(_ id: String?) {
        sessionPipeId = id
        pill.model.selectedPipeId = id
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        stopTicking()
        let rec = recorder.stop()
        let purpose = self.purpose
        let pipe = pipeStore.pipe(id: sessionPipeId)
        let cfg = config
        pickerSelection = nil

        if rec.duration < 0.3 || rec.peak < 0.01 {
            phase = .idle
            pill.flash("Didn't catch any speech")
            return
        }

        phase = .processing
        pill.show(.processing("Transcribing…"))
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let wav = try WAV.writeTemp(samples: rec.samples)
                defer { try? FileManager.default.removeItem(at: wav) }
                let transcript = try await transcription.transcribe(wav: wav, config: cfg.transcription)
                try Task.checkCancellation()
                guard !transcript.isEmpty else {
                    finish(message: "Didn't catch any speech")
                    return
                }

                switch purpose {
                case .dictate:
                    var output = transcript
                    var warning: String?
                    if let pipe, cfg.llm.enabled {
                        if AnthropicClient.apiKey == nil {
                            warning = "No ANTHROPIC_API_KEY, pasted the raw transcript"
                        } else {
                            pill.show(.processing(pipe.name + "…"))
                            do {
                                output = try await llm.transform(text: transcript, instructions: pipe.prompt, config: cfg.llm)
                                if output.isEmpty { output = transcript }
                            } catch {
                                if Task.isCancelled { throw CancellationError() }
                                warning = "\(pipe.name) failed, pasted the raw transcript. \(error.localizedDescription)"
                            }
                        }
                    }
                    try Task.checkCancellation()
                    TextIO.insert(output, restorePrevious: cfg.clipboard.restorePrevious, restoreDelayMs: cfg.clipboard.restoreDelayMs)
                    finish(message: warning, isError: true)

                case .instruction(let selection):
                    pill.show(.processing("“\(transcript)”"))
                    let output = try await llm.transform(text: selection, instructions: transcript, config: cfg.llm)
                    try Task.checkCancellation()
                    TextIO.insert(output, restorePrevious: cfg.clipboard.restorePrevious, restoreDelayMs: cfg.clipboard.restoreDelayMs)
                    finish(message: nil)
                }
            } catch {
                if Task.isCancelled { return }
                finish(message: error.localizedDescription, isError: true)
            }
        }
    }

    private func finish(message: String?, isError: Bool = false) {
        work = nil
        phase = .idle
        if let message { pill.flash(message, isError: isError, seconds: isError ? 4 : 1.6) } else { pill.hide() }
    }

    // MARK: Transform picker

    private func openPicker(selection: String) {
        pickerSelection = selection
        phase = .picker
        let m = pill.model
        m.pipes = pipeStore.pipes
        m.hotkeyLabel = HotkeySpec.label(config.hotkey)
        m.selectionPreview = selection.replacingOccurrences(of: "\n", with: " ")
        pill.show(.picker)
    }

    private func closePicker() {
        guard phase == .picker else { return }
        pickerSelection = nil
        phase = .idle
        pill.hide()
    }

    private func speakInstructionClicked() {
        guard phase == .picker, let sel = pickerSelection else { return }
        purpose = .instruction(sel)
        // A click can't be "held", so go straight to hands-free; tap the hotkey or the stop button to finish.
        startRecording(mode: .handsFree)
    }

    private func runPipeOnSelection(_ pipe: TextPipe) {
        guard phase == .picker, let selection = pickerSelection else { return }
        pickerSelection = nil
        let cfg = config
        phase = .processing
        pill.show(.processing(pipe.name + "…"))
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await llm.transform(text: selection, instructions: pipe.prompt, config: cfg.llm)
                try Task.checkCancellation()
                TextIO.insert(output, restorePrevious: cfg.clipboard.restorePrevious, restoreDelayMs: cfg.clipboard.restoreDelayMs)
                finish(message: nil)
            } catch {
                if Task.isCancelled { return }
                finish(message: error.localizedDescription, isError: true)
            }
        }
    }
}
