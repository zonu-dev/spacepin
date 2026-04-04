import AppKit
import Combine
import SpacePinCore

@MainActor
final class PinContentViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    private let item: PinItem
    private let initialContentSize: CGSize
    private let imageURL: () -> URL?
    private let onDelete: () -> Void
    private let onDuplicate: () -> Void
    var onToggleCollapse: (() -> Void)?
    var onCollapsedResizeCommitted: ((CGRect) -> Void)?

    private let cardView = NSView()
    private let headerView = NSView()
    private let contentContainer = NSView()
    private let iconView = DragForwardingImageView()
    private let titleField = TitleTextField()
    private let headerDragView = DragForwardingView()
    private let leadingResizeHandle = HorizontalResizeHandleView(edge: .leading)
    private let trailingResizeHandle = HorizontalResizeHandleView(edge: .trailing)
    private let clickThroughIconView = NSImageView()
    private lazy var colorButton = makeHeaderButton(
        systemName: "paintpalette",
        action: #selector(handleColorButton)
    )
    private lazy var lockButton = makeHeaderButton(
        systemName: "lock.open",
        action: #selector(handleLockToggle)
    )
    private lazy var collapseButton = makeHeaderButton(
        systemName: "rectangle.compress.vertical",
        action: #selector(handleCollapseToggle)
    )
    private lazy var duplicateButton = makeHeaderButton(
        systemName: "plus.square.on.square",
        action: #selector(handleDuplicate)
    )
    private lazy var deleteButton = makeHeaderButton(
        systemName: "xmark",
        action: #selector(handleDelete)
    )

    private let scrollView = NSScrollView()
    private let textView = PinTextView()
    private let imageContainer = NSView()
    private let imageView = ShrinkableImageView()
    private let placeholderIcon = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private var recordCancellable: AnyCancellable?
    private var isEditingTitle = false

    init(
        item: PinItem,
        initialContentSize: CGSize,
        onToggleCollapse: (() -> Void)? = nil,
        imageURL: @escaping () -> URL?,
        onDelete: @escaping () -> Void,
        onDuplicate: @escaping () -> Void
    ) {
        self.item = item
        self.initialContentSize = initialContentSize
        self.onToggleCollapse = onToggleCollapse
        self.imageURL = imageURL
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.setFrameSize(initialContentSize)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        configureHierarchy()
        apply(record: item.record)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        recordCancellable = item.$record.sink { [weak self] record in
            self?.apply(record: record)
        }
    }

    func textDidChange(_ notification: Notification) {
        applyNoteTextAppearance(
            theme: item.record.noteColorPreset.theme,
            fontSize: item.record.noteFontSize
        )
        item.updateNoteText(textView.string)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === titleField else {
            return
        }

        isEditingTitle = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === titleField else {
            return
        }

        isEditingTitle = false
        commitTitleEdit()
        titleField.isEditable = false
        titleField.isSelectable = false
    }

    func handleWindowResignKey() {
        commitTitleEdit()

        guard item.record.kind == .note else {
            return
        }

        let collapsedRange = NSRange(location: textView.selectedRange().location, length: 0)
        textView.setSelectedRange(collapsedRange.clamped(to: textView.string.utf16.count))
    }

    @objc
    private func handleDuplicate() {
        onDuplicate()
    }

    @objc
    private func handleDelete() {
        onDelete()
    }

    @objc
    private func handleCollapseToggle() {
        onToggleCollapse?()
    }

    @objc
    private func handleLockToggle() {
        item.setLocked(!item.record.locked)
    }

    @objc
    private func handleColorButton() {
        guard item.record.kind == .note else {
            return
        }

        let menu = NSMenu()
        for preset in NoteColorPreset.allCases {
            let menuItem = NSMenuItem(
                title: L10n.noteColorName(preset),
                action: #selector(handleColorSelection(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = preset.rawValue
            menuItem.state = item.record.noteColorPreset == preset ? .on : .off
            menu.addItem(menuItem)
        }

        let origin = NSPoint(x: 0, y: colorButton.bounds.height + 6)
        menu.popUp(positioning: nil, at: origin, in: colorButton)
    }

    @objc
    private func handleColorSelection(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let preset = NoteColorPreset(rawValue: rawValue)
        else {
            return
        }

        item.setNoteColorPreset(preset)
    }

    private func configureHierarchy() {
        view.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 18
        cardView.layer?.masksToBounds = true
        cardView.layer?.borderWidth = 1

        cardView.addSubview(headerView)
        cardView.addSubview(contentContainer)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: cardView.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 34),

            contentContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        configureHeader()
        configureNoteArea()
        configureImageArea()
    }

    private func configureHeader() {
        let leadingStack = NSStackView()
        leadingStack.orientation = .horizontal
        leadingStack.alignment = .centerY
        leadingStack.spacing = 8
        leadingStack.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.contentTintColor = .labelColor
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
        ])

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.delegate = self
        titleField.onRenameRequested = { [weak self] in
            self?.beginTitleEditing()
        }
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.usesSingleLineMode = true
        titleField.cell?.wraps = false
        titleField.cell?.isScrollable = false
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])

        leadingStack.addArrangedSubview(iconView)
        leadingStack.addArrangedSubview(titleField)

        let trailingStack = NSStackView()
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 10
        trailingStack.translatesAutoresizingMaskIntoConstraints = false

        headerDragView.translatesAutoresizingMaskIntoConstraints = false
        headerDragView.canDragWindow = !item.record.locked
        headerDragView.toolTip = item.record.locked ? nil : L10n.text("tooltip.drag_to_move", fallback: "Drag to move")

        clickThroughIconView.translatesAutoresizingMaskIntoConstraints = false
        clickThroughIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        clickThroughIconView.image = NSImage(
            systemSymbolName: "hand.raised.slash",
            accessibilityDescription: L10n.text("accessibility.click_through_enabled", fallback: "Click-through enabled")
        )
        clickThroughIconView.isHidden = true
        NSLayoutConstraint.activate([
            clickThroughIconView.widthAnchor.constraint(equalToConstant: 14),
            clickThroughIconView.heightAnchor.constraint(equalToConstant: 14),
        ])

        colorButton.toolTip = L10n.text("tooltip.change_note_color", fallback: "Change Note Color")
        lockButton.toolTip = L10n.text("tooltip.toggle_lock", fallback: "Toggle Lock")
        collapseButton.toolTip = L10n.text("tooltip.collapse_pin", fallback: "Collapse Pin")
        duplicateButton.toolTip = L10n.text("tooltip.duplicate_pin", fallback: "Duplicate Pin")
        deleteButton.toolTip = L10n.text("tooltip.delete_pin", fallback: "Delete Pin")

        trailingStack.addArrangedSubview(clickThroughIconView)
        trailingStack.addArrangedSubview(colorButton)
        trailingStack.addArrangedSubview(lockButton)
        trailingStack.addArrangedSubview(collapseButton)
        trailingStack.addArrangedSubview(duplicateButton)
        trailingStack.addArrangedSubview(deleteButton)

        headerView.addSubview(leadingStack)
        headerView.addSubview(headerDragView)
        headerView.addSubview(trailingStack)
        headerView.addSubview(leadingResizeHandle)
        headerView.addSubview(trailingResizeHandle)

        leadingResizeHandle.translatesAutoresizingMaskIntoConstraints = false
        trailingResizeHandle.translatesAutoresizingMaskIntoConstraints = false
        leadingResizeHandle.minimumWidth = PinPanel.collapsedMinimumWidth
        trailingResizeHandle.minimumWidth = PinPanel.collapsedMinimumWidth
        leadingResizeHandle.onResizeEnded = { [weak self] frame in
            self?.onCollapsedResizeCommitted?(frame)
        }
        trailingResizeHandle.onResizeEnded = { [weak self] frame in
            self?.onCollapsedResizeCommitted?(frame)
        }

        NSLayoutConstraint.activate([
            leadingStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            leadingStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            headerDragView.leadingAnchor.constraint(equalTo: leadingStack.trailingAnchor, constant: 8),
            headerDragView.trailingAnchor.constraint(equalTo: trailingStack.leadingAnchor, constant: -8),
            headerDragView.topAnchor.constraint(equalTo: headerView.topAnchor),
            headerDragView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            trailingStack.leadingAnchor.constraint(greaterThanOrEqualTo: headerDragView.trailingAnchor, constant: 8),
            trailingStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            trailingStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            leadingResizeHandle.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            leadingResizeHandle.topAnchor.constraint(equalTo: headerView.topAnchor),
            leadingResizeHandle.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            leadingResizeHandle.widthAnchor.constraint(equalToConstant: 14),

            trailingResizeHandle.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            trailingResizeHandle.topAnchor.constraint(equalTo: headerView.topAnchor),
            trailingResizeHandle.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            trailingResizeHandle.widthAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func configureNoteArea() {
        contentContainer.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false

        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = noteFont(size: item.record.noteFontSize)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.typingAttributes = noteTypingAttributes(
            theme: item.record.noteColorPreset.theme,
            fontSize: item.record.noteFontSize
        )
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func configureImageArea() {
        contentContainer.addSubview(imageContainer)
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.wantsLayer = true

        imageContainer.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)

        let placeholderStack = NSStackView()
        placeholderStack.orientation = .vertical
        placeholderStack.alignment = .centerX
        placeholderStack.spacing = 8
        placeholderStack.translatesAutoresizingMaskIntoConstraints = false

        placeholderIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        placeholderIcon.image = NSImage(
            systemSymbolName: "photo",
            accessibilityDescription: L10n.text("accessibility.missing_image", fallback: "Missing image")
        )
        placeholderIcon.contentTintColor = .white
        placeholderIcon.alphaValue = 0.85

        placeholderLabel.stringValue = L10n.text(
            "placeholder.image_failed_to_load",
            fallback: "Image could not be loaded."
        )
        placeholderLabel.textColor = NSColor.white.withAlphaComponent(0.85)

        placeholderStack.addArrangedSubview(placeholderIcon)
        placeholderStack.addArrangedSubview(placeholderLabel)
        imageContainer.addSubview(placeholderStack)

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            imageContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            imageContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 10),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -10),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 10),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -10),

            placeholderStack.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            placeholderStack.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
        ])
    }

    private func apply(record: PinRecord) {
        let isNote = record.kind == .note
        let noteTheme = record.noteColorPreset.theme
        let noteFont = noteFont(size: record.noteFontSize)
        let headerTextColor = isNote ? noteTheme.headerText : NSColor.white

        cardView.layer?.backgroundColor = (isNote
            ? noteTheme.bodyBackground
            : NSColor(calibratedWhite: 0.08, alpha: 1.0)).cgColor
        cardView.layer?.borderColor = (isNote
            ? noteTheme.border
            : NSColor.white.withAlphaComponent(0.12)).cgColor
        headerView.layer?.backgroundColor = (isNote
            ? noteTheme.headerBackground
            : NSColor.black.withAlphaComponent(0.55)).cgColor

        iconView.image = NSImage(
            systemSymbolName: isNote ? "note.text" : "photo",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = headerTextColor
        iconView.canDragWindow = !record.locked
        if !isEditingTitle {
            titleField.stringValue = record.localizedDisplayTitle
        }
        titleField.textColor = headerTextColor
        titleField.canDragWindow = !record.locked
        titleField.canRename = !record.locked
        titleField.toolTip = record.locked
            ? nil
            : L10n.text("tooltip.double_click_to_rename", fallback: "Double-click to rename")
        headerDragView.canDragWindow = !record.locked
        headerDragView.toolTip = record.locked
            ? nil
            : L10n.text("tooltip.drag_to_move", fallback: "Drag to move")

        clickThroughIconView.contentTintColor = headerTextColor.withAlphaComponent(0.9)
        clickThroughIconView.isHidden = !record.clickThrough
        colorButton.isHidden = !isNote
        colorButton.contentTintColor = isNote ? noteTheme.swatch : headerTextColor
        lockButton.image = NSImage(
            systemSymbolName: record.locked ? "lock.fill" : "lock.open",
            accessibilityDescription: record.locked
                ? L10n.text("accessibility.unlock_pin", fallback: "Unlock Pin")
                : L10n.text("accessibility.lock_pin", fallback: "Lock Pin")
        )
        lockButton.contentTintColor = headerTextColor
        collapseButton.image = NSImage(
            systemSymbolName: record.isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
            accessibilityDescription: record.isCollapsed
                ? L10n.text("accessibility.expand_pin", fallback: "Expand Pin")
                : L10n.text("accessibility.collapse_pin", fallback: "Collapse Pin")
        )
        collapseButton.toolTip = record.isCollapsed
            ? L10n.text("tooltip.expand_pin", fallback: "Expand Pin")
            : L10n.text("tooltip.collapse_pin", fallback: "Collapse Pin")
        collapseButton.contentTintColor = headerTextColor
        duplicateButton.contentTintColor = headerTextColor
        deleteButton.contentTintColor = headerTextColor
        leadingResizeHandle.isEnabled = record.isCollapsed && !record.locked
        trailingResizeHandle.isEnabled = record.isCollapsed && !record.locked
        leadingResizeHandle.isHidden = !leadingResizeHandle.isEnabled
        trailingResizeHandle.isHidden = !trailingResizeHandle.isEnabled

        contentContainer.isHidden = record.isCollapsed
        scrollView.isHidden = !isNote || record.isCollapsed
        imageContainer.isHidden = isNote || record.isCollapsed
        textView.isEditable = isNote && !record.locked
        textView.isSelectable = isNote && !record.locked
        textView.font = noteFont
        textView.textColor = isNote ? noteTheme.bodyText : NSColor.textColor
        textView.insertionPointColor = isNote ? noteTheme.headerText : NSColor.textColor
        textView.selectedTextAttributes = [
            .backgroundColor: noteTheme.selectionBackground,
            .foregroundColor: noteTheme.selectionText,
        ]
        textView.typingAttributes = noteTypingAttributes(theme: noteTheme, fontSize: record.noteFontSize)

        if record.locked {
            let collapsedRange = NSRange(location: min(textView.selectedRange().location, record.noteText.utf16.count), length: 0)
            textView.setSelectedRange(collapsedRange)
        }

        if textView.string != record.noteText {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: record.noteText,
                    attributes: noteTypingAttributes(theme: noteTheme, fontSize: record.noteFontSize)
                )
            )
            textView.setSelectedRange(selectedRange.clamped(to: record.noteText.utf16.count))
        }

        if isNote {
            applyNoteTextAppearance(theme: noteTheme, fontSize: record.noteFontSize)
        }

        if !isNote {
            let image = imageURL().flatMap(NSImage.init(contentsOf:))
            imageView.image = image
            imageView.isHidden = image == nil
            placeholderIcon.isHidden = image != nil
            placeholderLabel.isHidden = image != nil
        }
    }

    private func makeHeaderButton(systemName: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: action
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalToConstant: 16),
        ])
        return button
    }

    private func applyNoteTextAppearance(theme: NoteTheme, fontSize: Double) {
        guard let textStorage = textView.textStorage else {
            return
        }

        let selectedRange = textView.selectedRange()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let noteFont = noteFont(size: fontSize)

        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: noteFont,
            .foregroundColor: theme.bodyText,
        ], range: fullRange)
        textStorage.endEditing()

        textView.setSelectedRange(selectedRange)
    }

    private func noteTypingAttributes(theme: NoteTheme, fontSize: Double) -> [NSAttributedString.Key: Any] {
        [
            .font: noteFont(size: fontSize),
            .foregroundColor: theme.bodyText,
        ]
    }

    private func noteFont(size: Double) -> NSFont {
        NSFont.systemFont(ofSize: CGFloat(size), weight: .medium)
    }

    private func beginTitleEditing() {
        guard !item.record.locked else {
            return
        }

        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.selectText(nil)
    }

    private func commitTitleEdit() {
        item.setTitle(titleField.stringValue)
        titleField.stringValue = item.record.localizedDisplayTitle
    }
}

private final class ShrinkableImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private final class PinTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

private final class DragForwardingImageView: NSImageView {
    var canDragWindow = true

    override func mouseDown(with event: NSEvent) {
        guard canDragWindow else {
            return
        }

        window?.performDrag(with: event)
    }
}

private final class TitleTextField: NSTextField {
    var canDragWindow = true
    var canRename = true
    var onRenameRequested: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if isEditable {
            super.mouseDown(with: event)
            return
        }

        if event.clickCount == 2, canRename {
            onRenameRequested?()
            return
        }

        guard canDragWindow else {
            return
        }

        window?.performDrag(with: event)
    }
}

private final class DragForwardingView: NSView {
    var canDragWindow = true

    override func mouseDown(with event: NSEvent) {
        guard canDragWindow else {
            return
        }

        window?.performDrag(with: event)
    }
}

private final class HorizontalResizeHandleView: NSView {
    enum Edge {
        case leading
        case trailing
    }

    var isEnabled = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var minimumWidth: CGFloat = PinPanel.collapsedMinimumWidth
    var onResizeEnded: ((CGRect) -> Void)?

    private let edge: Edge
    private var initialMouseLocation: NSPoint?
    private var initialFrame: CGRect?
    private var fixedHeight: CGFloat?
    private var fixedMaxY: CGFloat?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        discardCursorRects()

        guard isEnabled else {
            return
        }

        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else {
            return
        }

        initialMouseLocation = mouseLocationInScreen(for: event, window: window)
        initialFrame = window.frame
        fixedHeight = window.frame.height
        fixedMaxY = window.frame.maxY
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            isEnabled,
            let window,
            let initialMouseLocation,
            let initialFrame
        else {
            return
        }

        let currentLocation = mouseLocationInScreen(for: event, window: window)
        let deltaX = currentLocation.x - initialMouseLocation.x
        let lockedHeight = fixedHeight ?? initialFrame.height
        let lockedMaxY = fixedMaxY ?? initialFrame.maxY
        let nextFrame: CGRect

        switch edge {
        case .leading:
            let width = max(minimumWidth, initialFrame.width - deltaX)
            nextFrame = CGRect(
                x: initialFrame.maxX - width,
                y: lockedMaxY - lockedHeight,
                width: width,
                height: lockedHeight
            )
        case .trailing:
            let width = max(minimumWidth, initialFrame.width + deltaX)
            nextFrame = CGRect(
                x: initialFrame.minX,
                y: lockedMaxY - lockedHeight,
                width: width,
                height: lockedHeight
            )
        }

        window.setFrame(nextFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if isEnabled, let window {
            onResizeEnded?(window.frame)
        }

        initialMouseLocation = nil
        initialFrame = nil
        fixedHeight = nil
        fixedMaxY = nil
    }

    private func mouseLocationInScreen(for event: NSEvent, window: NSWindow) -> NSPoint {
        window.convertPoint(toScreen: event.locationInWindow)
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let safeLocation = max(0, min(location, length))
        let remaining = max(0, length - safeLocation)
        let safeLength = max(0, min(self.length, remaining))
        return NSRange(location: safeLocation, length: safeLength)
    }
}
