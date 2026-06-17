import UIKit

// MARK: - DocsSectionHeader

private class DocsSectionHeader: UITableViewHeaderFooterView {
    let iconView  = UIImageView()
    let titleLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        let bg = UIView()
        bg.backgroundColor = .systemGroupedBackground
        backgroundView = bg

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        contentView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)

        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: -6.0),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10.0),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14.0),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6.0),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(symbol: String, tint: UIColor, title: String) {
        let cfg = UIImage.SymbolConfiguration(font: titleLabel.font, scale: .small)
        iconView.image = UIImage(systemName: symbol, withConfiguration: cfg)
        iconView.tintColor = tint
        titleLabel.text = title
    }
}

// MARK: - DocsFooter

private class DocsFooter: UITableViewHeaderFooterView {
    let body = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        let bg = UIView()
        bg.backgroundColor = .systemGroupedBackground
        backgroundView = bg

        body.translatesAutoresizingMaskIntoConstraints = false
        body.numberOfLines = 0
        body.font = UIFont.preferredFont(forTextStyle: .footnote)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = .secondaryLabel
        contentView.addSubview(body)

        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            body.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8.0),
            body.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18.0),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String) { body.text = text }
}

// MARK: - DocsCell

private class DocsCell: UITableViewCell {
    let bodyView       = UITextView()
    let codeBackground = UIView()
    let filenameLabel  = UILabel()
    let divider        = UIView()
    var dividerHeight: NSLayoutConstraint!

    private var proseConstraints: [NSLayoutConstraint] = []
    private var codeConstraints:  [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        contentView.backgroundColor = .clear

        codeBackground.translatesAutoresizingMaskIntoConstraints = false
        codeBackground.backgroundColor = .tertiarySystemGroupedBackground
        codeBackground.layer.cornerRadius = 10.0
        codeBackground.layer.cornerCurve = .continuous
        codeBackground.layer.masksToBounds = true
        codeBackground.isHidden = true
        contentView.addSubview(codeBackground)

        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        filenameLabel.font = .monospacedSystemFont(ofSize: 11.0, weight: .medium)
        filenameLabel.textColor = .secondaryLabel
        codeBackground.addSubview(filenameLabel)

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        codeBackground.addSubview(divider)
        dividerHeight = divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)

        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.isScrollEnabled = false
        bodyView.isEditable = false
        bodyView.backgroundColor = .clear
        bodyView.textContainerInset = .zero
        bodyView.textContainer.lineFragmentPadding = 0.0
        bodyView.dataDetectorTypes = .link
        bodyView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        bodyView.adjustsFontForContentSizeCategory = true
        bodyView.alwaysBounceVertical = false
        contentView.addSubview(bodyView)

        proseConstraints = [
            bodyView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9.0),
            bodyView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9.0),
            bodyView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18.0),
            bodyView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18.0),
        ]
        codeConstraints = [
            codeBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6.0),
            codeBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6.0),
            codeBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12.0),
            codeBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.0),

            filenameLabel.topAnchor.constraint(equalTo: codeBackground.topAnchor, constant: 9.0),
            filenameLabel.leadingAnchor.constraint(equalTo: codeBackground.leadingAnchor, constant: 14.0),
            filenameLabel.trailingAnchor.constraint(lessThanOrEqualTo: codeBackground.trailingAnchor, constant: -14.0),

            divider.topAnchor.constraint(equalTo: filenameLabel.bottomAnchor, constant: 8.0),
            divider.leadingAnchor.constraint(equalTo: codeBackground.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: codeBackground.trailingAnchor),
            dividerHeight,

            bodyView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10.0),
            bodyView.bottomAnchor.constraint(equalTo: codeBackground.bottomAnchor, constant: -12.0),
            bodyView.leadingAnchor.constraint(equalTo: codeBackground.leadingAnchor, constant: 14.0),
            bodyView.trailingAnchor.constraint(equalTo: codeBackground.trailingAnchor, constant: -14.0),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    func configureProse(text: String) {
        NSLayoutConstraint.deactivate(codeConstraints)
        NSLayoutConstraint.activate(proseConstraints)
        codeBackground.isHidden = true
        bodyView.textContainer.maximumNumberOfLines = 0
        bodyView.textContainer.lineBreakMode = .byWordWrapping

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3.0
        para.paragraphSpacing = 10.0
        bodyView.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: para,
        ])
    }

    func configureCode(text: String, filename: String) {
        NSLayoutConstraint.deactivate(proseConstraints)
        NSLayoutConstraint.activate(codeConstraints)
        codeBackground.isHidden = false
        filenameLabel.text = filename
        dividerHeight.constant = 1.0 / UIScreen.main.scale
        bodyView.textContainer.maximumNumberOfLines = 0
        bodyView.textContainer.lineBreakMode = .byWordWrapping

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2.0
        let baseMono = UIFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
        let mono = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: baseMono)
        bodyView.attributedText = NSAttributedString(string: text, attributes: [
            .font: mono,
            .foregroundColor: UIColor.label,
            .paragraphStyle: para,
        ])
    }
}

// MARK: - DocsViewController

private let kProseCellID = "DocsProseCell"
private let kCodeCellID  = "DocsCodeCell"
private let kHeaderID    = "DocsSectionHeader"
private let kFooterID    = "DocsFooter"

private struct DocsRow {
    enum Kind { case prose, code }
    let kind: Kind
    let text: String
    let filename: String
}

private struct DocsSection {
    let title:  String
    let symbol: String
    let tint:   UIColor
    let footer: String
    let rows:   [DocsRow]
}

@objc class DocsViewController: UITableViewController {

    private var sections: [DocsSection] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Docs"
        navigationItem.title = "Docs"

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80.0
        tableView.estimatedSectionHeaderHeight = 60.0
        tableView.estimatedSectionFooterHeight = 40.0
        tableView.separatorStyle = .none
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 28, right: 0)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 6.0
        }
        tableView.register(DocsCell.self,          forCellReuseIdentifier: kProseCellID)
        tableView.register(DocsCell.self,          forCellReuseIdentifier: kCodeCellID)
        tableView.register(DocsSectionHeader.self, forHeaderFooterViewReuseIdentifier: kHeaderID)
        tableView.register(DocsFooter.self,        forHeaderFooterViewReuseIdentifier: kFooterID)

        buildSections()
    }

    // MARK: - Content

    private func buildSections() {
        let helloHeader =
            "#ifndef hello_tweak_h\n" +
            "#define hello_tweak_h\n" +
            "#include <stdbool.h>\n" +
            "bool hello_tweak_apply_in_session(void);\n" +
            "bool hello_tweak_stop_in_session(void);\n" +
            "void hello_tweak_forget_remote_state(void);\n" +
            "#endif"

        let helloImpl =
            "#import \"hello_tweak.h\"\n" +
            "#import \"remote_objc.h\"\n" +
            "#import \"../TaskRop/RemoteCall.h\"\n" +
            "#import <stdint.h>\n" +
            "\n" +
            "static const uint64_t kHelloTag = 0xC0A11DE;\n" +
            "static uint64_t gHelloView = 0;\n" +
            "\n" +
            "static uint64_t hello_first_window(void) {\n" +
            "    uint64_t UIApplication = r_class(\"UIApplication\");\n" +
            "    uint64_t app = r_msg2_main(UIApplication, \"sharedApplication\",\n" +
            "                               0, 0, 0, 0);\n" +
            "    if (!r_is_objc_ptr(app)) return 0;\n" +
            "\n" +
            "    uint64_t keyWindow = r_msg2_main(app, \"keyWindow\", 0, 0, 0, 0);\n" +
            "    if (r_is_objc_ptr(keyWindow)) return keyWindow;\n" +
            "\n" +
            "    uint64_t windows = r_msg2_main(app, \"windows\", 0, 0, 0, 0);\n" +
            "    uint64_t count = r_msg2_main(windows, \"count\", 0, 0, 0, 0);\n" +
            "    for (uint64_t i = 0; r_is_objc_ptr(windows) && i < count && i < 16; i++) {\n" +
            "        uint64_t window = r_msg2_main(windows, \"objectAtIndex:\", i, 0, 0, 0);\n" +
            "        if (r_is_objc_ptr(window)) return window;\n" +
            "    }\n" +
            "    return 0;\n" +
            "}\n" +
            "\n" +
            "static uint64_t hello_existing_view(uint64_t window) {\n" +
            "    if (!r_is_objc_ptr(window)) return 0;\n" +
            "    uint64_t view = r_msg2_main(window, \"viewWithTag:\", kHelloTag, 0, 0, 0);\n" +
            "    if (r_is_objc_ptr(view)) gHelloView = view;\n" +
            "    return r_is_objc_ptr(view) ? view : 0;\n" +
            "}\n" +
            "\n" +
            "bool hello_tweak_apply_in_session(void) {\n" +
            "    uint64_t window = hello_first_window();\n" +
            "    if (!r_is_objc_ptr(window)) return false;\n" +
            "\n" +
            "    uint64_t existing = hello_existing_view(window);\n" +
            "    if (r_is_objc_ptr(existing)) {\n" +
            "        r_msg2_main(existing, \"setHidden:\", 0, 0, 0, 0);\n" +
            "        r_msg2_main(window, \"bringSubviewToFront:\", existing, 0, 0, 0);\n" +
            "        return true;\n" +
            "    }\n" +
            "\n" +
            "    uint64_t UIView = r_class(\"UIView\");\n" +
            "    uint64_t view = r_msg2_main(r_msg2_main(UIView, \"alloc\", 0, 0, 0, 0),\n" +
            "                                \"init\", 0, 0, 0, 0);\n" +
            "    if (!r_is_objc_ptr(view)) return false;\n" +
            "\n" +
            "    struct { double x, y, w, h; } frame = { 40.0, 120.0, 80.0, 80.0 };\n" +
            "    r_msg2_main_raw(view, \"setFrame:\",\n" +
            "                    &frame, sizeof(frame),\n" +
            "                    NULL, 0, NULL, 0, NULL, 0);\n" +
            "\n" +
            "    uint64_t UIColor = r_class(\"UIColor\");\n" +
            "    uint64_t color = r_msg2_main(UIColor, \"systemRedColor\", 0, 0, 0, 0);\n" +
            "    if (!r_is_objc_ptr(color)) color = r_msg2_main(UIColor, \"redColor\", 0, 0, 0, 0);\n" +
            "    r_msg2_main(view, \"setBackgroundColor:\", color, 0, 0, 0);\n" +
            "    r_msg2_main(view, \"setTag:\", kHelloTag, 0, 0, 0);\n" +
            "    r_msg2_main(window, \"addSubview:\", view, 0, 0, 0);\n" +
            "    r_msg2_main(view, \"release\", 0, 0, 0, 0);\n" +
            "\n" +
            "    gHelloView = view;\n" +
            "    return true;\n" +
            "}\n" +
            "\n" +
            "bool hello_tweak_stop_in_session(void) {\n" +
            "    uint64_t window = hello_first_window();\n" +
            "    uint64_t view = hello_existing_view(window);\n" +
            "    if (!r_is_objc_ptr(view)) return false;\n" +
            "\n" +
            "    r_msg2_main(view, \"setHidden:\", 1, 0, 0, 0);\n" +
            "    r_msg2_main(view, \"removeFromSuperview\", 0, 0, 0, 0);\n" +
            "    gHelloView = 0;\n" +
            "    return true;\n" +
            "}\n" +
            "\n" +
            "void hello_tweak_forget_remote_state(void) {\n" +
            "    // SpringBoard respawned or RemoteCall was abandoned; cached\n" +
            "    // remote pointers are from the old address space.\n" +
            "    gHelloView = 0;\n" +
            "}"

        let wiring =
            "#import \"tweaks/hello_tweak.h\"\n" +
            "NSString * const kSettingsHelloEnabled = @\"HelloEnabled\";\n" +
            "\n" +
            "// Add kSettingsHelloEnabled to settings_register_defaults(),\n" +
            "// settings_rc_backed_tweak_keys(), settings_key_affects_package_state(),\n" +
            "// and the Settings rows that render the switch.\n" +
            "static BOOL settings_key_is_hello(NSString *key) {\n" +
            "    return [key isEqualToString:kSettingsHelloEnabled];\n" +
            "}\n" +
            "\n" +
            "// In the Run path, after settings_ensure_springboard_remote_call_locked():\n" +
            "if ([d boolForKey:kSettingsHelloEnabled]) {\n" +
            "    bool ok = hello_tweak_apply_in_session();\n" +
            "    settings_mark_tweak_applied(kSettingsHelloEnabled,\n" +
            "                                ok && [d boolForKey:kSettingsHelloEnabled]);\n" +
            "    printf(\"[SETTINGS] Hello result=%d\\n\", ok);\n" +
            "}\n" +
            "\n" +
            "// In settings_schedule_live_apply_for_key():\n" +
            "if (settings_key_is_hello(key)) {\n" +
            "    if ([d boolForKey:kSettingsHelloEnabled] && g_springboard_rc_ready) {\n" +
            "        dispatch_async(dispatch_get_global_queue(0, 0), ^{\n" +
            "            @synchronized (settings_rc_lock()) {\n" +
            "                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;\n" +
            "                bool ok = hello_tweak_apply_in_session();\n" +
            "                settings_mark_tweak_applied(kSettingsHelloEnabled,\n" +
            "                                            ok && [d boolForKey:kSettingsHelloEnabled]);\n" +
            "            }\n" +
            "            settings_notify_package_queue_changed_async();\n" +
            "        });\n" +
            "    } else if (![d boolForKey:kSettingsHelloEnabled]) {\n" +
            "        settings_mark_tweak_applied(kSettingsHelloEnabled, NO);\n" +
            "        settings_notify_package_queue_changed_async();\n" +
            "        if (g_springboard_rc_ready) dispatch_async(dispatch_get_global_queue(0, 0), ^{\n" +
            "            @synchronized (settings_rc_lock()) {\n" +
            "                if (g_springboard_rc_ready) hello_tweak_stop_in_session();\n" +
            "            }\n" +
            "        });\n" +
            "    }\n" +
            "    return;\n" +
            "}\n" +
            "\n" +
            "// In SpringBoard restart/abandon and manual cleanup paths:\n" +
            "hello_tweak_forget_remote_state();"

        let apiCheat =
            "#import \"remote_objc.h\"\n" +
            "#import \"../TaskRop/RemoteCall.h\"\n" +
            "\n" +
            "r_class(\"UILabel\")                  // remote Class *\n" +
            "r_sel(\"setHidden:\")                 // remote SEL\n" +
            "r_msg2(obj, \"setHidden:\", 1,0,0,0)  // objc_msgSend in target\n" +
            "r_msg2_main(label, \"setText:\", text,\n" +
            "            0,0,0)                   // UIKit/main-thread send\n" +
            "r_msg2_main_raw(obj, \"setFrame:\",\n" +
            "  &rect, sizeof(rect), NULL,0,\n" +
            "  NULL,0, NULL,0)                    // pass a struct by value\n" +
            "r_msg2_main_struct_ret(obj, \"bounds\",\n" +
            "  &out, sizeof(out), NULL,0,\n" +
            "  NULL,0, NULL,0, NULL,0)            // copy a struct return\n" +
            "\n" +
            "r_alloc_str(\"hi\") / r_free(ptr)     // C string into remote\n" +
            "r_nsstr_retained(\"hi\")              // NSString*, caller releases\n" +
            "r_cfstr(\"hi\")                       // CFStringRef, caller CFReleases\n" +
            "r_settle_us(1000)                    // tune helper delay; restore old value\n" +
            "\n" +
            "r_dlsym_call(R_TIMEOUT,\n" +
            "  \"objc_setAssociatedObject\",\n" +
            "  obj, key, val, policy, 0,0,0,0)    // any C function\n" +
            "r_is_objc_ptr(p)                     // sanity check\n" +
            "r_ivar_value(obj, \"_name\")          // read ivar\n" +
            "r_responds_main(obj, \"sel:\")        // -respondsToSelector:\n" +
            "remote_read / remote_write           // raw memory helpers\n" +
            "init_remote_call(\"SpringBoard\", false)\n" +
            "destroy_remote_call()                // one-shot sessions only\n" +
            "abandon_remote_call()                // remote task is already gone"

        let portingNotes =
            "%hook UIView                         not portable as a hook\n" +
            "- (void)setHidden:(BOOL)h { ... }    rewrite as explicit\n" +
            "                                     r_msg2_main(view,\n" +
            "                                     \"setHidden:\", h,0,0,0)\n" +
            "\n" +
            "[%c(Foo) bar]                        r_msg2(r_class(\"Foo\"),\n" +
            "                                           \"bar\", 0,0,0,0)\n" +
            "\n" +
            "struct { double x,y,w,h; } r = {0};  r_msg2_main_struct_ret(view,\n" +
            "                                     \"bounds\", &r, sizeof(r),\n" +
            "                                     NULL,0, NULL,0, NULL,0, NULL,0)\n" +
            "\n" +
            "%new -[X cyanideOverlay]             associated object via\n" +
            "                                     objc_setAssociatedObject\n" +
            "                                     through r_dlsym_call\n" +
            "\n" +
            "MSHookFunction(...)                  not available here"

        sections = [
            DocsSection(
                title: "How tweaks work",
                symbol: "book.closed.fill",
                tint: .systemPurple,
                footer: "Read sbcustomizer.m, statbar.m, rssidisplay.m, and axonlite.m in "
                      + "Cyanide/tweaks/ for shipped patterns at increasing complexity.",
                rows: [
                    DocsRow(kind: .prose, text:
                        "Cyanide tweaks are app-side drivers. No SpringBoard dylibs, no "
                        + "Substrate hooks, no swizzled methods. The app reaches into the "
                        + "target from outside.", filename: ""),
                    DocsRow(kind: .prose, text:
                        "A RemoteCall session is the bridge. From inside one you send "
                        + "Objective-C messages, read and write memory, and call C symbols "
                        + "in the target process.", filename: ""),
                    DocsRow(kind: .prose, text:
                        "Settings holds the SpringBoard channel during Apply Tweaks. Your "
                        + "code runs inside it under settings_rc_lock(), via three "
                        + "entrypoints: apply_in_session, optional stop_in_session, and "
                        + "forget_remote_state.", filename: ""),
                ]
            ),
            DocsSection(
                title: "The remote_objc API",
                symbol: "chevron.left.forwardslash.chevron.right",
                tint: .systemBlue,
                footer: "_main variants dispatch to the target main thread (use them for "
                      + "UIKit). _raw passes non-pointer arguments by value. "
                      + "r_msg2_main_struct_ret copies struct returns such as CGRect.",
                rows: [
                    DocsRow(kind: .prose, text:
                        "Import remote_objc.h and ../TaskRop/RemoteCall.h. Helpers assume "
                        + "an active session — don't call init_remote_call yourself unless "
                        + "you need a private channel.", filename: ""),
                    DocsRow(kind: .code, text: apiCheat, filename: "remote_objc.h"),
                ]
            ),
            DocsSection(
                title: "A minimal tweak",
                symbol: "doc.text.fill",
                tint: .systemOrange,
                footer: "Drop both files in Cyanide/tweaks/. The Xcode project uses "
                      + "PBXFileSystemSynchronizedRootGroup, so new files are picked up "
                      + "automatically — no pbxproj edits needed.",
                rows: [
                    DocsRow(kind: .prose, text:
                        "A complete RemoteCall-only tweak: paints an 80×80 red square on "
                        + "a SpringBoard window.", filename: ""),
                    DocsRow(kind: .prose, text:
                        "Idempotent on reapply, undoes itself on stop, drops cached "
                        + "pointers on respawn.", filename: ""),
                    DocsRow(kind: .code, text: helloHeader, filename: "hello_tweak.h"),
                    DocsRow(kind: .code, text: helloImpl,   filename: "hello_tweak.m"),
                ]
            ),
            DocsSection(
                title: "Wiring into Settings",
                symbol: "gearshape.2.fill",
                tint: .systemGreen,
                footer: "Mirror an existing kSettings…Enabled path — search "
                      + "kSettingsStatBarEnabled or kSettingsAxonLiteEnabled for a complete "
                      + "template covering defaults, rows, package state, Run, live apply, "
                      + "stop, and cleanup.",
                rows: [
                    DocsRow(kind: .prose, text:
                        "SettingsViewController.m is the orchestrator. Add five things: a "
                        + "defaults key, a switch row, a Run-path apply, a live-apply "
                        + "branch, and forget_remote_state in cleanup.", filename: ""),
                    DocsRow(kind: .prose, text:
                        "Every apply checks g_springboard_rc_ready inside "
                        + "@synchronized(settings_rc_lock()). settings_mark_tweak_applied() "
                        + "keeps package state honest. forget_remote_state() runs on "
                        + "respring and abandon.", filename: ""),
                    DocsRow(kind: .code, text: wiring, filename: "SettingsViewController.m"),
                ]
            ),
            DocsSection(
                title: "Porting from Theos / Substrate",
                symbol: "arrow.triangle.2.circlepath",
                tint: .systemPink,
                footer: "Shipped templates: sbcustomizer (dock layout), darksword_tweaks "
                      + "(SpringBoard state toggles), powercuff (thermalmonitord one-shot), "
                      + "statbar (overlay window), rssidisplay (per-icon overlays), "
                      + "axonlite (cached NC state).",
                rows: [
                    DocsRow(kind: .prose, text:
                        "RemoteCall isn't a hook framework. You can't intercept a method "
                        + "or replace a C function in place.", filename: ""),
                    DocsRow(kind: .prose, text:
                        "Ports work when the effect is a finite mutation — set this "
                        + "property, call this controller method, add this view, hold this "
                        + "assertion, or refresh on a timer.", filename: ""),
                    DocsRow(kind: .code, text: portingNotes, filename: "Theos → RemoteCall"),
                    DocsRow(kind: .prose, text:
                        "Targeting another process? Open a separate session with "
                        + "init_remote_call(name, false), do the work, destroy_remote_call "
                        + "before switching back. Powercuff does this for thermalmonitord.", filename: ""),
                ]
            ),
            DocsSection(
                title: "Contribute",
                symbol: "arrow.up.right.square.fill",
                tint: .systemRed,
                footer: "",
                rows: [
                    DocsRow(kind: .prose, text:
                        "Build with ./scripts/build.sh — the IPA is packaged under "
                        + "build/. Sideload, test on device, attach Log-tab output to your "
                        + "PR.", filename: ""),
                    DocsRow(kind: .prose, text:
                        "Source and issues: https://github.com/zeroxjf/cyanide", filename: ""),
                ]
            ),
        ]
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let isCode = row.kind == .code
        let cell = tableView.dequeueReusableCell(
            withIdentifier: isCode ? kCodeCellID : kProseCellID,
            for: indexPath) as! DocsCell
        if isCode {
            cell.configureCode(text: row.text, filename: row.filename)
        } else {
            cell.configureProse(text: row.text)
        }
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let s = sections[section]
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: kHeaderID) as! DocsSectionHeader
        header.configure(symbol: s.symbol, tint: s.tint, title: s.title)
        return header
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let text = sections[section].footer
        guard !text.isEmpty else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: kFooterID) as! DocsFooter
        footer.configure(text: text)
        return footer
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        sections[section].footer.isEmpty ? .leastNormalMagnitude : UITableView.automaticDimension
    }
}
