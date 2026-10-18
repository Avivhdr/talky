import AppKit

/// The dictation state machine.
///
/// Main hotkey:
///   hold                     -> record while held, transcribe on release
///   short tap, short tap     -> hands-free; the next press stops and transcribes
///   short single tap         -> ignored (recording discarded)
/// Hands-free hotkey: a tap starts a hands-free recording, the next tap stops and transcribes.
/// Saved-dictations hotkey: a tap opens that Settings page. It does not record.
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
    let snippetStore: SnippetStore
    let pill = PillController()
    let recorder = AudioRecorder()
    public let transcription = TranscriptionService()
    let llm = AnthropicClient()

    public private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    public var onPhaseChange: ((Phase) -> Void)?
    /// Called when the hotkey is pressed before Talky can record: no speech model, or no microphone access.
    public var onNeedsSetup: (() -> Void)?
    /// A tap of the saved-dictations hotkey. The app opens that Settings page. This does not change the recording.
    public var onOpenSavedDictations: (() -> Void)?

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

    public init(configStore: ConfigStore, pipeStore: PipeStore, snippetStore: SnippetStore) {
        self.configStore = configStore
        self.pipeStore = pipeStore
        self.snippetStore = snippetStore
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
            if let problem = recordingProblem { return showRecordingProblem(problem) }
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

    public func savedDictationsHotkeyFired() {
        onOpenSavedDictations?()
    }

    public func handsFreeHotkeyFired() {
        switch phase {
        case .recording:
            // Held or hands-free, a tap ends it. A main hotkey still down then has nothing to finish.
            mainDownAt = nil
            finishRecording()
        case .idle, .picker:
            if let problem = recordingProblem { return showRecordingProblem(problem) }
            lastTapUpAt = nil
            if phase == .picker, let sel = pickerSelection {
                purpose = .instruction(sel)
            } else {
                purpose = .dictate
            }
            startRecording(mode: .handsFree)
        case .processing:
            break
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

    public func pickerKeyPressed(_ key: PickerKey) -> Bool {
        // "Speak an instruction" from the picker records hands-free. Return finishes it, as fn does,
        // instead of reaching the app and replacing the selection with a new line.
        if phase == .recording, mode == .handsFree, case .instruction = purpose, key == .choose {
            finishRecording()
            return true
        }
        guard phase == .picker else { return false }
        let m = pill.model
        let pipes = Array(pipeStore.pipes.prefix(9))
        let rows = pipes.count + 1 // the pipes, then "Speak an instruction"
        switch key {
        case .up: m.highlighted = (m.highlighted - 1 + rows) % rows
        case .down: m.highlighted = (m.highlighted + 1) % rows
        case .choose:
            if m.highlighted < pipes.count { runPipeOnSelection(pipes[m.highlighted]) } else { speakInstructionClicked() }
        }
        return true
    }

    public func otherKeyWhileHeld() {
        guard phase == .recording, mode == .hold, let down = mainDownAt,
              Date().timeIntervalSince(down) < Self.chordGrace else { return }
        mainDownAt = nil
        lastTapUpAt = nil
        ignoreNextMainUp = true
        abortRecording()
    }

    /// Stops what is in flight and frees the speech model, before the app exits.
    public func shutDown() {
        work?.cancel()
        work = nil
        stopTicking()
        recorder.cancel()
        transcription.unload()
    }

    // MARK: Recording

    /// Why Talky can't record now, or nil when it can.
    private var recordingProblem: String? { Permissions.microphoneProblem ?? SpeechModel.shared.blocker }

    /// Says why Talky can't record, and starts the fix: the macOS prompt, or the window with the missing step.
    private func showRecordingProblem(_ problem: String) {
        pill.flash(problem, seconds: 2.5)
        if Permissions.microphoneProblem != nil {
            // macOS asks only the first time. After that, only System Settings can change the answer.
            if Permissions.microphoneUndecided { Permissions.requestMicrophone() } else { onNeedsSetup?() }
        } else if !SpeechModel.shared.isDownloading {
            onNeedsSetup?()
        }
    }

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
        let samples = rec.samples

        phase = .processing
        pill.show(.processing("Transcribing…"))
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = try await transcription.transcribe(samples: samples, config: cfg.transcription)
                try Task.checkCancellation()
                guard !transcript.isEmpty else {
                    finish(message: "Didn't catch any speech")
                    return
                }

                switch purpose {
                case .dictate:
                    var output = transcript
                    var warning: String?
                    var pipeName: String?
                    var piped: String?
                    if let pipe, cfg.llm.enabled {
                        pipeName = pipe.name
                        if AnthropicClient.apiKey == nil {
                            warning = "No ANTHROPIC_API_KEY, pasted the raw transcript"
                        } else {
                            pill.show(.processing(pipe.name + "…"))
                            do {
                                let transformed = try await llm.transform(text: transcript, instructions: pipe.prompt, config: cfg.llm)
                                if !transformed.isEmpty {
                                    output = transformed
                                    piped = transformed
                                }
                            } catch {
                                if Task.isCancelled { throw CancellationError() }
                                warning = "\(pipe.name) failed, pasted the raw transcript. \(error.localizedDescription)"
                            }
                        }
                    }
                    try Task.checkCancellation()
                    snippetStore.record(kind: .dictation, original: transcript, pipeName: pipeName, piped: piped, samples: samples)
                    TextIO.insert(output, restorePrevious: cfg.clipboard.restorePrevious, restoreDelayMs: cfg.clipboard.restoreDelayMs)
                    finish(message: warning, isError: true)

                case .instruction(let selection):
                    pill.show(.processing("“\(transcript)”"))
                    let output = try await llm.transform(text: selection, instructions: transcript, config: cfg.llm)
                    try Task.checkCancellation()
                    snippetStore.record(kind: .instruction, original: transcript, pipeName: nil, piped: output, samples: samples)
                    TextIO.insert(output, restorePrevious: cfg.clipboard.restorePrevious, restoreDelayMs: cfg.clipboard.restoreDelayMs)
                    NotificationCenter.default.post(name: .talkySelectionTransformed, object: nil)
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
        m.highlighted = 0
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
        if let problem = recordingProblem {
            closePicker()
            showRecordingProblem(problem)
            return
        }
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
                NotificationCenter.default.post(name: .talkySelectionTransformed, object: nil)
                finish(message: nil)
            } catch {
                if Task.isCancelled { return }
                finish(message: error.localizedDescription, isError: true)
            }
        }
    }
}

extension Notification.Name {
    /// Posted after a pipe or a spoken instruction replaced the selected text.
    static let talkySelectionTransformed = Notification.Name("TalkySelectionTransformed")
}
