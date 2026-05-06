import AppKit
import Combine
import SpacePinCore
import SwiftUI

@MainActor
final class PinContentViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    enum HeaderIconSelection: Hashable {
        case titleInitial
        case symbol(String)
    }

    private static let headerIconSymbolOptions: [String] = [
        "note.text",
        "doc.text",
        "doc.richtext",
        "doc.on.doc",
        "bookmark",
        "flag",
        "heart",
        "star",
        "bell",
        "calendar",
        "clock",
        "checkmark.circle",
        "checkmark.seal",
        "exclamationmark.triangle",
        "questionmark.circle",
        "paperclip",
        "link",
        "message",
        "bubble.left",
        "phone",
        "envelope",
        "tray",
        "archivebox",
        "externaldrive",
        "internaldrive",
        "shippingbox",
        "folder",
        "tag",
        "cart",
        "bag",
        "suitcase",
        "briefcase",
        "lock",
        "key",
        "shield",
        "camera",
        "photo",
        "film",
        "music.note",
        "headphones",
        "mic",
        "video",
        "gamecontroller",
        "message.and.waveform",
        "paintpalette",
        "pencil",
        "hammer",
        "wrench.and.screwdriver",
        "lightbulb",
        "sparkles",
        "wand.and.stars",
        "graduationcap",
        "book.closed",
        "book",
        "newspaper",
        "map",
        "location",
        "globe",
        "airplane",
        "car",
        "tram",
        "ferry",
        "bicycle",
        "figure.walk",
        "figure.run",
        "person",
        "person.2",
        "house",
        "building.2",
        "storefront",
        "sun.max",
        "moon",
        "cloud",
        "drop",
        "snowflake",
        "flame",
        "bolt",
        "leaf",
        "tree",
        "pawprint",
        "gift",
        "balloon.2",
        "cup.and.saucer",
        "fork.knife",
        "birthday.cake",
        "wineglass",
        "medal",
        "trophy",
        "target",
        "binoculars",
        "dice",
        "puzzlepiece",
        "theatermasks",
        "terminal",
        "desktopcomputer",
        "laptopcomputer",
        "display",
        "printer",
        "scanner",
        "wifi",
        "battery.100",
        "powerplug",
    ]

    private let item: PinItem
    private let initialContentSize: CGSize
    private let imageURL: () -> URL?
    private let onDelete: () -> Void
    var onToggleCollapse: (() -> Void)?
    var onToggleVerticalZoom: (() -> Void)?
    var onCollapsedResizeCommitted: ((CGRect) -> Void)?
    var onCompactDragEnded: ((CGPoint) -> Void)?
    var onCompactDragMoved: ((CGPoint) -> Void)?
    var onCompactDragStateChanged: ((Bool) -> Void)?

    private let cardView = NSView()
    private let headerView = NSView()
    private let contentContainer = NSView()
    private let compactNoteView = CompactNoteControl()
    private var expandedLayoutConstraints: [NSLayoutConstraint] = []
    private lazy var iconButton = makeHeaderIconButton(action: #selector(handleHeaderIconButton))
    private let titleField = TitleTextField()
    private let headerDragView = DragForwardingView()
    private let leadingResizeHandle = HorizontalResizeHandleView(edge: .leading)
    private let trailingResizeHandle = HorizontalResizeHandleView(edge: .trailing)
    private let clickThroughIconView = NSImageView()
    private lazy var deleteButton = makeTrafficLightButton(
        symbol: .close,
        fillColor: TrafficLightButton.closeFillColor,
        accessibilityLabel: L10n.text("tooltip.delete_pin", fallback: "Delete Pin"),
        action: #selector(handleDelete)
    )
    private lazy var collapseButton = makeTrafficLightButton(
        symbol: .collapse,
        fillColor: TrafficLightButton.collapseFillColor,
        accessibilityLabel: L10n.text("tooltip.collapse_pin", fallback: "Collapse Pin"),
        action: #selector(handleCollapseToggle)
    )
    private lazy var verticalZoomButton = makeTrafficLightButton(
        symbol: .verticalZoomOutward,
        fillColor: TrafficLightButton.zoomFillColor,
        accessibilityLabel: L10n.text("tooltip.toggle_vertical_zoom", fallback: "Toggle Height"),
        action: #selector(handleVerticalZoomToggle)
    )
    private lazy var editTitleButton = makeHeaderButton(
        systemName: "square.and.pencil",
        action: #selector(handleEditTitle)
    )
    private lazy var colorButton = makeHeaderButton(
        systemName: "paintpalette",
        action: #selector(handleColorButton)
    )

    private let scrollView = NSScrollView()
    private let textView = PinTextView()
    private let imageContainer = NSView()
    private let imageView = ShrinkableImageView()
    private let placeholderIcon = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private var recordCancellable: AnyCancellable?
    private var iconPickerPopover: NSPopover?
    private var isEditingTitle = false

    init(
        item: PinItem,
        initialContentSize: CGSize,
        onToggleCollapse: (() -> Void)? = nil,
        imageURL: @escaping () -> URL?,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.initialContentSize = initialContentSize
        self.onToggleCollapse = onToggleCollapse
        self.imageURL = imageURL
        self.onDelete = onDelete
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

    func setVerticalZoomed(_ isVerticalZoomed: Bool) {
        verticalZoomButton.symbol = isVerticalZoomed ? .verticalZoomInward : .verticalZoomOutward
    }

    @objc
    private func handleDelete() {
        onDelete()
    }

    @objc
    private func handleEditTitle() {
        beginTitleEditing()
    }

    @objc
    private func handleHeaderIconButton() {
        if let iconPickerPopover, iconPickerPopover.isShown {
            iconPickerPopover.performClose(nil)
            self.iconPickerPopover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let record = item.record
        let frameTheme = record.frameColorPreset.theme
        let pickerView = HeaderIconPickerView(
            currentInitial: record.localizedHeaderMonogram,
            selectedSelection: selectedHeaderIconSelection(for: record),
            symbolNames: Self.headerIconSymbolOptions,
            accentColor: frameTheme.swatch,
            onSelectTitleInitial: { [weak self, weak popover] in
                self?.item.setHeaderIconToTitleInitial()
                popover?.performClose(nil)
                self?.iconPickerPopover = nil
            },
            onSelectSymbol: { [weak self, weak popover] symbolName in
                self?.item.setHeaderIconSymbolName(symbolName)
                popover?.performClose(nil)
                self?.iconPickerPopover = nil
            }
        )

        let hostingController = NSHostingController(rootView: pickerView)
        popover.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        popover.contentSize = hostingController.view.fittingSize
        popover.show(relativeTo: iconButton.bounds, of: iconButton, preferredEdge: .maxY)
        iconPickerPopover = popover
    }

    private func selectedHeaderIconSelection(for record: PinRecord) -> HeaderIconSelection {
        if record.headerIconMode == .titleInitial {
            return .titleInitial
        }

        return .symbol(record.headerIconSymbolName)
    }

    @objc
    private func handleCollapseToggle() {
        onToggleCollapse?()
    }

    @objc
    private func handleVerticalZoomToggle() {
        onToggleVerticalZoom?()
    }

    @objc
    private func handleColorButton() {
        let menu = NSMenu()
        for preset in NoteColorPreset.allCases {
            let menuItem = NSMenuItem(
                title: L10n.noteColorName(preset),
                action: #selector(handleColorSelection(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = preset.rawValue
            menuItem.state = item.record.frameColorPreset == preset ? .on : .off
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

        item.setFrameColorPreset(preset)
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
        cardView.addSubview(compactNoteView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        compactNoteView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            compactNoteView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            compactNoteView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            compactNoteView.topAnchor.constraint(equalTo: cardView.topAnchor),
            compactNoteView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        expandedLayoutConstraints = [
            headerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: cardView.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 34),
            contentContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(expandedLayoutConstraints)

        configureHeader()
        configureNoteArea()
        configureImageArea()
        configureCompactNoteView()
    }

    private func configureHeader() {
        let trafficStack = NSStackView()
        trafficStack.orientation = .horizontal
        trafficStack.alignment = .centerY
        trafficStack.spacing = 7
        trafficStack.translatesAutoresizingMaskIntoConstraints = false

        let leadingStack = NSStackView()
        leadingStack.orientation = .horizontal
        leadingStack.alignment = .centerY
        leadingStack.spacing = 8
        leadingStack.translatesAutoresizingMaskIntoConstraints = false

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.delegate = self
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

        leadingStack.addArrangedSubview(iconButton)
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

        editTitleButton.toolTip = L10n.text("tooltip.edit_title", fallback: "Edit Title")
        colorButton.toolTip = L10n.text("tooltip.change_note_color", fallback: "Change Note Color")
        collapseButton.toolTip = L10n.text("tooltip.collapse_pin", fallback: "Collapse Pin")
        deleteButton.toolTip = L10n.text("tooltip.delete_pin", fallback: "Delete Pin")
        verticalZoomButton.toolTip = L10n.text("tooltip.toggle_vertical_zoom", fallback: "Toggle Height")

        trafficStack.addArrangedSubview(deleteButton)
        trafficStack.addArrangedSubview(collapseButton)
        trafficStack.addArrangedSubview(verticalZoomButton)
        trailingStack.addArrangedSubview(clickThroughIconView)
        trailingStack.addArrangedSubview(editTitleButton)
        trailingStack.addArrangedSubview(colorButton)

        headerView.addSubview(trafficStack)
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
            trafficStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            trafficStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            leadingStack.leadingAnchor.constraint(equalTo: trafficStack.trailingAnchor, constant: 12),
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

    private func configureCompactNoteView() {
        compactNoteView.onActivate = { [weak self] in
            self?.onToggleCollapse?()
        }
        compactNoteView.onDragEnded = { [weak self] point in
            self?.onCompactDragEnded?(point)
        }
        compactNoteView.onDragMoved = { [weak self] point in
            self?.onCompactDragMoved?(point)
        }
        compactNoteView.onDragStateChanged = { [weak self] isDragging in
            self?.onCompactDragStateChanged?(isDragging)
        }
    }

    private func apply(record: PinRecord) {
        let isNote = record.kind == .note
        let isCompactPin = record.isCollapsed
        let frameTheme = record.frameColorPreset.theme
        let noteFont = noteFont(size: record.noteFontSize)
        let headerTextColor = frameTheme.headerText
        let compactButtonBorderColor = frameTheme.swatch.withAlphaComponent(0.95)
        let compactButtonShadowColor = frameTheme.swatch.withAlphaComponent(0.22)

        cardView.layer?.backgroundColor = (isCompactPin
            ? frameTheme.headerBackground
            : frameTheme.bodyBackground).cgColor
        cardView.layer?.borderColor = frameTheme.border.cgColor
        cardView.layer?.cornerRadius = isCompactPin ? PinPanel.compactNoteDiameter / 2 : 18
        cardView.layer?.masksToBounds = !isCompactPin
        headerView.layer?.backgroundColor = frameTheme.headerBackground.cgColor

        iconButton.toolTip = L10n.text("tooltip.change_icon", fallback: "Change Icon")
        applyHeaderIconButtonAppearance(record: record, textColor: headerTextColor)
        compactNoteView.symbolName = record.headerIconSymbolName
        compactNoteView.iconTintColor = frameTheme.bodyText
        compactNoteView.buttonBackgroundColor = frameTheme.bodyBackground
        compactNoteView.buttonBorderColor = compactButtonBorderColor
        compactNoteView.buttonShadowColor = compactButtonShadowColor
        compactNoteView.canDragWindow = !record.locked
        compactNoteView.toolTip = L10n.text("tooltip.expand_pin", fallback: "Expand Pin")
        if !isEditingTitle {
            titleField.stringValue = record.localizedDisplayTitle
        }
        titleField.textColor = headerTextColor
        titleField.canDragWindow = !record.locked
        titleField.toolTip = record.locked
            ? nil
            : L10n.text("tooltip.drag_to_move", fallback: "Drag to move")
        headerDragView.canDragWindow = !record.locked
        headerDragView.toolTip = record.locked
            ? nil
            : L10n.text("tooltip.drag_to_move", fallback: "Drag to move")

        clickThroughIconView.contentTintColor = headerTextColor.withAlphaComponent(0.9)
        clickThroughIconView.isHidden = !record.clickThrough
        editTitleButton.isEnabled = !record.locked
        editTitleButton.toolTip = record.locked ? nil : L10n.text("tooltip.edit_title", fallback: "Edit Title")
        editTitleButton.contentTintColor = headerTextColor
        colorButton.isHidden = record.kind == .image && record.isCollapsed
        colorButton.toolTip = isNote
            ? L10n.text("tooltip.change_note_color", fallback: "Change Note Color")
            : L10n.text("tooltip.change_frame_color", fallback: "Change Frame Color")
        colorButton.contentTintColor = headerTextColor
        collapseButton.toolTip = record.isCollapsed
            ? L10n.text("tooltip.expand_pin", fallback: "Expand Pin")
            : L10n.text("tooltip.collapse_pin", fallback: "Collapse Pin")
        verticalZoomButton.toolTip = L10n.text("tooltip.toggle_vertical_zoom", fallback: "Toggle Height")
        leadingResizeHandle.isEnabled = false
        trailingResizeHandle.isEnabled = false
        leadingResizeHandle.isHidden = true
        trailingResizeHandle.isHidden = true

        headerView.isHidden = isCompactPin
        compactNoteView.isHidden = !isCompactPin
        contentContainer.isHidden = record.isCollapsed
        setExpandedLayoutActive(!isCompactPin)
        scrollView.isHidden = !isNote || record.isCollapsed
        imageContainer.isHidden = isNote || record.isCollapsed
        textView.isEditable = isNote && !record.locked
        textView.isSelectable = isNote && !record.locked
        textView.font = noteFont
        textView.textColor = isNote ? frameTheme.bodyText : NSColor.textColor
        textView.insertionPointColor = isNote ? frameTheme.headerText : NSColor.textColor
        textView.selectedTextAttributes = [
            .backgroundColor: frameTheme.selectionBackground,
            .foregroundColor: frameTheme.selectionText,
        ]
        textView.typingAttributes = noteTypingAttributes(theme: frameTheme, fontSize: record.noteFontSize)

        if record.locked {
            let collapsedRange = NSRange(location: min(textView.selectedRange().location, record.noteText.utf16.count), length: 0)
            textView.setSelectedRange(collapsedRange)
        }

        if textView.string != record.noteText {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: record.noteText,
                    attributes: noteTypingAttributes(theme: frameTheme, fontSize: record.noteFontSize)
                )
            )
            textView.setSelectedRange(selectedRange.clamped(to: record.noteText.utf16.count))
        }

        if isNote {
            applyNoteTextAppearance(theme: frameTheme, fontSize: record.noteFontSize)
        }

        if !isNote {
            let image = imageURL().flatMap(NSImage.init(contentsOf:))
            imageView.image = image
            imageView.isHidden = image == nil
            placeholderIcon.isHidden = image != nil
            placeholderLabel.isHidden = image != nil
            let placeholderColor = frameTheme.bodyText.withAlphaComponent(0.85)
            placeholderIcon.contentTintColor = placeholderColor
            placeholderLabel.textColor = placeholderColor
        }
    }

    private func setExpandedLayoutActive(_ isActive: Bool) {
        guard expandedLayoutConstraints.contains(where: { $0.isActive != isActive }) else {
            return
        }

        if isActive {
            NSLayoutConstraint.activate(expandedLayoutConstraints)
        } else {
            NSLayoutConstraint.deactivate(expandedLayoutConstraints)
        }
    }

    private func makeHeaderIconButton(action: Selector) -> HeaderIconButton {
        let button = HeaderIconButton(target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = L10n.text("tooltip.change_icon", fallback: "Change Icon")
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: HeaderIconButton.diameter),
            button.heightAnchor.constraint(equalToConstant: HeaderIconButton.diameter),
        ])
        return button
    }

    private func makeHeaderButton(systemName: String, action: Selector) -> NSButton {
        makeHeaderButton(systemName: systemName, action: action, dimension: 16)
    }

    private func makeHeaderButton(systemName: String, action: Selector, dimension: CGFloat) -> NSButton {
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
            button.widthAnchor.constraint(equalToConstant: dimension),
            button.heightAnchor.constraint(equalToConstant: dimension),
        ])
        return button
    }

    private func makeTrafficLightButton(
        symbol: TrafficLightButton.Symbol,
        fillColor: NSColor,
        accessibilityLabel: String,
        action: Selector
    ) -> TrafficLightButton {
        let button = TrafficLightButton(
            symbol: symbol,
            fillColor: fillColor,
            accessibilityLabel: accessibilityLabel,
            target: self,
            action: action
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: TrafficLightButton.diameter),
            button.heightAnchor.constraint(equalToConstant: TrafficLightButton.diameter),
        ])
        return button
    }

    private func applyHeaderIconButtonAppearance(record: PinRecord, textColor: NSColor) {
        let frameTheme = record.frameColorPreset.theme
        iconButton.innerFillColor = frameTheme.bodyBackground
        iconButton.borderColor = frameTheme.swatch
        iconButton.iconColor = frameTheme.bodyText

        if record.headerIconMode == .titleInitial {
            iconButton.monogram = record.localizedHeaderMonogram
            iconButton.symbolName = nil
            return
        }

        iconButton.monogram = nil
        iconButton.symbolName = record.headerIconSymbolName
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

        isEditingTitle = true
        titleField.isEditable = true
        titleField.isSelectable = true
        view.window?.makeKey()
        view.window?.makeFirstResponder(titleField)
        positionTitleInsertionCursor()

        Task { @MainActor [weak self] in
            self?.positionTitleInsertionCursor()
        }
    }

    private func positionTitleInsertionCursor() {
        let insertionPoint = titleField.stringValue.utf16.count
        let selectedRange = NSRange(location: insertionPoint, length: 0)

        if let fieldEditor = titleField.currentEditor() as? NSTextView {
            fieldEditor.selectedRange = selectedRange
            fieldEditor.insertionPointColor = titleField.textColor ?? .labelColor
            fieldEditor.drawsBackground = false
            return
        }

        titleField.currentEditor()?.selectedRange = selectedRange
    }

    private func commitTitleEdit() {
        item.setTitle(titleField.stringValue)
        titleField.stringValue = item.record.localizedDisplayTitle
    }
}

private struct HeaderIconPickerView: View {
    @State private var hoveredSelection: PinContentViewController.HeaderIconSelection?

    let currentInitial: String
    let selectedSelection: PinContentViewController.HeaderIconSelection
    let symbolNames: [String]
    let accentColor: NSColor
    let onSelectTitleInitial: () -> Void
    let onSelectSymbol: (String) -> Void

    private let cellSize: CGFloat = 24
    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 12)

    var body: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectMaterialView(material: .popover)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onSelectTitleInitial) {
                    HStack(spacing: 10) {
                        selectionBackground(for: .titleInitial)
                            .overlay {
                                Text(currentInitial)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(foregroundColor(for: .titleInitial))
                            }
                            .frame(width: cellSize, height: cellSize)

                        Text(L10n.text("label.title_initial", fallback: "Title Initial"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 1)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredSelection = isHovering ? .titleInitial : clearedHover(for: .titleInitial)
                }

                Divider()

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(symbolNames, id: \.self) { symbolName in
                            Button {
                                onSelectSymbol(symbolName)
                            } label: {
                                selectionBackground(for: .symbol(symbolName))
                                    .overlay {
                                    Image(systemName: symbolName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(foregroundColor(for: .symbol(symbolName)))
                                    }
                                    .frame(width: cellSize, height: cellSize)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                let selection = PinContentViewController.HeaderIconSelection.symbol(symbolName)
                                hoveredSelection = isHovering ? selection : clearedHover(for: selection)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 396)
    }

    private func selectionBackground(for selection: PinContentViewController.HeaderIconSelection) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(backgroundFill(for: selection))
    }

    private func backgroundFill(for selection: PinContentViewController.HeaderIconSelection) -> Color {
        if selectedSelection == selection {
            return selectionFill
        }

        if hoveredSelection == selection {
            return hoverFill
        }

        return .clear
    }

    private func foregroundColor(for selection: PinContentViewController.HeaderIconSelection) -> Color {
        selectedSelection == selection ? Color(nsColor: accentColor) : .primary
    }

    private func clearedHover(for selection: PinContentViewController.HeaderIconSelection) -> PinContentViewController.HeaderIconSelection? {
        hoveredSelection == selection ? nil : hoveredSelection
    }

    private var selectionFill: Color {
        Color(nsColor: accentColor).opacity(0.18)
    }

    private var hoverFill: Color {
        Color.primary.opacity(0.10)
    }
}

private struct VisualEffectMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .withinWindow
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
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

private final class HeaderIconButton: NSButton {
    static let diameter: CGFloat = 30

    private static let shapeInset: CGFloat = 1
    private static let cornerRadius: CGFloat = 9
    private static let monogramFontSize: CGFloat = 14
    private static let symbolDrawSize: CGFloat = 16
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)

    var innerFillColor: NSColor = .windowBackgroundColor {
        didSet {
            needsDisplay = true
        }
    }
    var borderColor: NSColor = .separatorColor {
        didSet {
            needsDisplay = true
        }
    }
    var iconColor: NSColor = .labelColor {
        didSet {
            needsDisplay = true
        }
    }
    var symbolName: String? {
        didSet {
            symbolImage = symbolName.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                    .withSymbolConfiguration(Self.symbolConfiguration)
            }
            needsDisplay = true
        }
    }
    var monogram: String? {
        didSet {
            needsDisplay = true
        }
    }

    private var symbolImage: NSImage?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            needsDisplay = true
        }
    }

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)

        self.target = target
        self.action = action
        title = ""
        image = nil
        imagePosition = .noImage
        isBordered = false
        bezelStyle = .shadowlessSquare
        focusRingType = .none
        setButtonType(.momentaryChange)
        setAccessibilityLabel(L10n.text("tooltip.change_icon", fallback: "Change Icon"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.diameter, height: Self.diameter)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let iconRect = bounds.centeredSquare.insetBy(dx: Self.shapeInset, dy: Self.shapeInset)
        let iconPath = NSBezierPath(
            roundedRect: iconRect,
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        if isHovering {
            let shadow = NSShadow()
            shadow.shadowColor = borderColor.withAlphaComponent(0.14)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
        }
        innerFillColor.withAlphaComponent(isHighlighted ? 0.82 : 0.96).setFill()
        iconPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        borderColor.withAlphaComponent(isHovering ? 0.62 : 0.34).setStroke()
        iconPath.lineWidth = isHovering ? 1.0 : 0.8
        iconPath.stroke()

        if let monogram {
            drawMonogram(monogram, in: iconRect)
        } else if let symbolImage {
            drawSymbol(symbolImage, in: iconRect)
        }
    }

    private func drawMonogram(_ monogram: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Self.monogramFontSize, weight: .bold),
            .foregroundColor: iconColor.withAlphaComponent(isHighlighted ? 0.72 : 1.0),
        ]
        let textSize = monogram.size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 - 0.4,
            width: textSize.width,
            height: textSize.height
        )
        monogram.draw(in: textRect, withAttributes: attributes)
    }

    private func drawSymbol(_ image: NSImage, in rect: CGRect) {
        let symbolColor = iconColor.withAlphaComponent(isHighlighted ? 0.72 : 1.0)
        let symbolConfiguration = Self.symbolConfiguration.applying(
            NSImage.SymbolConfiguration(paletteColors: [symbolColor])
        )
        let coloredImage = image.withSymbolConfiguration(
            symbolConfiguration
        ) ?? image
        let imageSize = CGSize(width: Self.symbolDrawSize, height: Self.symbolDrawSize)
        let imageRect = CGRect(
            x: rect.midX - imageSize.width / 2,
            y: rect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        coloredImage.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
    }
}

private final class TrafficLightButton: NSButton {
    enum Symbol {
        case close
        case collapse
        case verticalZoomOutward
        case verticalZoomInward
    }

    static let diameter: CGFloat = 15
    static let closeFillColor = NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.32, alpha: 1.0)
    static let collapseFillColor = NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.13, alpha: 1.0)
    static let zoomFillColor = NSColor(calibratedRed: 0.22, green: 0.80, blue: 0.32, alpha: 1.0)

    private let fillColor: NSColor
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            applyAppearance()
        }
    }
    var symbol: Symbol {
        didSet {
            needsDisplay = true
        }
    }

    init(symbol: Symbol, fillColor: NSColor, accessibilityLabel: String, target: AnyObject?, action: Selector) {
        self.symbol = symbol
        self.fillColor = fillColor
        super.init(frame: .zero)

        self.target = target
        self.action = action
        setAccessibilityLabel(accessibilityLabel)
        title = ""
        image = nil
        imagePosition = .noImage
        isBordered = false
        bezelStyle = .shadowlessSquare
        focusRingType = .none
        setButtonType(.momentaryChange)
        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            applyAppearance()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.diameter, height: Self.diameter)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.centeredSquare.insetBy(dx: 0.5, dy: 0.5)
        let circlePath = NSBezierPath(ovalIn: circleRect)
        fillColor.withAlphaComponent(backgroundAlpha).setFill()
        circlePath.fill()

        NSColor.black.withAlphaComponent(isHovering ? 0.16 : 0.08).setStroke()
        circlePath.lineWidth = 0.5
        circlePath.stroke()

        iconColor.set()
        switch symbol {
        case .close:
            drawCloseIcon(in: circleRect)
        case .collapse:
            drawCollapseIcon(in: circleRect)
        case .verticalZoomOutward:
            drawVerticalZoomIcon(in: circleRect, pointsOutward: true)
        case .verticalZoomInward:
            drawVerticalZoomIcon(in: circleRect, pointsOutward: false)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    private func applyAppearance() {
        needsDisplay = true
    }

    private var backgroundAlpha: CGFloat {
        guard isEnabled else {
            return 0.42
        }

        return isHighlighted ? 0.76 : (isHovering ? 1.0 : 0.94)
    }

    private var iconColor: NSColor {
        let baseColor = fillColor.blended(withFraction: 0.48, of: .black) ?? .black
        let alpha: CGFloat
        if isEnabled {
            alpha = isHovering ? 0.82 : 0.68
        } else {
            alpha = 0.35
        }

        return baseColor.withAlphaComponent(alpha)
    }

    private func drawCloseIcon(in rect: CGRect) {
        let inset: CGFloat = 4.4
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.line(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.line(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.stroke()
    }

    private func drawCollapseIcon(in rect: CGRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.9
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: rect.minX + 4.3, y: rect.midY))
        path.line(to: CGPoint(x: rect.maxX - 4.3, y: rect.midY))
        path.stroke()
    }

    private func drawVerticalZoomIcon(in rect: CGRect, pointsOutward: Bool) {
        let centerX = rect.midX
        let centerY = rect.midY
        let radius: CGFloat = 2.9
        let gap: CGFloat = 0.65

        if pointsOutward {
            drawTriangle(
                tip: CGPoint(x: centerX, y: centerY + gap + radius),
                baseLeft: CGPoint(x: centerX - radius, y: centerY + gap),
                baseRight: CGPoint(x: centerX + radius, y: centerY + gap)
            )
            drawTriangle(
                tip: CGPoint(x: centerX, y: centerY - gap - radius),
                baseLeft: CGPoint(x: centerX - radius, y: centerY - gap),
                baseRight: CGPoint(x: centerX + radius, y: centerY - gap)
            )
        } else {
            drawTriangle(
                tip: CGPoint(x: centerX, y: centerY + gap),
                baseLeft: CGPoint(x: centerX - radius, y: centerY + gap + radius),
                baseRight: CGPoint(x: centerX + radius, y: centerY + gap + radius)
            )
            drawTriangle(
                tip: CGPoint(x: centerX, y: centerY - gap),
                baseLeft: CGPoint(x: centerX - radius, y: centerY - gap - radius),
                baseRight: CGPoint(x: centerX + radius, y: centerY - gap - radius)
            )
        }
    }

    private func drawTriangle(tip: CGPoint, baseLeft: CGPoint, baseRight: CGPoint) {
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: baseLeft)
        path.line(to: baseRight)
        path.close()
        path.fill()
    }
}

private extension CGRect {
    var centeredSquare: CGRect {
        let side = min(width, height)
        return CGRect(
            x: midX - side / 2,
            y: midY - side / 2,
            width: side,
            height: side
        )
    }
}

private final class TitleTextField: NSTextField {
    var canDragWindow = true

    override func mouseDown(with event: NSEvent) {
        if isEditable {
            super.mouseDown(with: event)
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

private final class CompactNoteControl: NSView {
    private static let buttonDiameter: CGFloat = 20

    var symbolName: String? {
        didSet {
            let image = symbolName.flatMap {
                NSImage(
                    systemSymbolName: $0,
                    accessibilityDescription: L10n.text("tooltip.expand_pin", fallback: "Expand Pin")
                )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
            }
            iconView.image = image
        }
    }

    var iconTintColor: NSColor? {
        didSet {
            iconView.contentTintColor = iconTintColor
        }
    }

    var buttonBackgroundColor: NSColor? {
        didSet {
            buttonFrameView.layer?.backgroundColor = buttonBackgroundColor?.cgColor
        }
    }

    var buttonBorderColor: NSColor? {
        didSet {
            buttonFrameView.layer?.borderColor = buttonBorderColor?.cgColor
        }
    }

    var buttonShadowColor: NSColor? {
        didSet {
            buttonFrameView.layer?.shadowColor = buttonShadowColor?.cgColor
        }
    }

    var canDragWindow = true
    var onActivate: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    private let buttonFrameView = NSView()
    private let iconView = NSImageView()
    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: CGRect?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        initialMouseLocation = mouseLocationInScreen(for: event, window: window)
        initialWindowFrame = window.frame
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            canDragWindow,
            let window,
            let initialMouseLocation,
            let initialWindowFrame
        else {
            return
        }

        let currentLocation = mouseLocationInScreen(for: event, window: window)
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y

        if !didDrag, hypot(deltaX, deltaY) < 4 {
            return
        }

        if !didDrag {
            onDragStateChanged?(true)
        }
        didDrag = true
        let nextOrigin = NSPoint(
            x: initialWindowFrame.origin.x + deltaX,
            y: initialWindowFrame.origin.y + deltaY
        )
        window.setFrameOrigin(nextOrigin)
        onDragMoved?(currentLocation)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            initialMouseLocation = nil
            initialWindowFrame = nil
            didDrag = false
        }

        guard let window else {
            return
        }

        guard !didDrag else {
            onDragEnded?(mouseLocationInScreen(for: event, window: window))
            onDragStateChanged?(false)
            return
        }

        onActivate?()
    }

    private func configure() {
        buttonFrameView.translatesAutoresizingMaskIntoConstraints = false
        buttonFrameView.wantsLayer = true
        buttonFrameView.layer?.cornerRadius = Self.buttonDiameter / 2
        buttonFrameView.layer?.borderWidth = 1
        buttonFrameView.layer?.shadowOpacity = 1
        buttonFrameView.layer?.shadowRadius = 3
        buttonFrameView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        buttonFrameView.layer?.shadowPath = CGPath(
            ellipseIn: CGRect(
                x: 0,
                y: 0,
                width: Self.buttonDiameter,
                height: Self.buttonDiameter
            ),
            transform: nil
        )

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)

        addSubview(buttonFrameView)
        buttonFrameView.addSubview(iconView)

        NSLayoutConstraint.activate([
            buttonFrameView.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonFrameView.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonFrameView.widthAnchor.constraint(equalToConstant: Self.buttonDiameter),
            buttonFrameView.heightAnchor.constraint(equalToConstant: Self.buttonDiameter),

            iconView.centerXAnchor.constraint(equalTo: buttonFrameView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: buttonFrameView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func mouseLocationInScreen(for event: NSEvent, window: NSWindow) -> NSPoint {
        window.convertPoint(toScreen: event.locationInWindow)
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
