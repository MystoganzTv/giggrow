//
//  KeyboardDoneBar.swift
//  GigGrow
//
//  A way off the number pad.
//
//  `.decimalPad` and `.numberPad` have no return key. Put one on screen with
//  nothing above it and the keyboard cannot be dismissed at all: the field
//  keeps focus, the content behind is covered, and the only way out is to
//  force-quit. This app shipped that bug three times, on three screens, and
//  each time it was fixed only where it happened to be noticed.
//
//  So it stops being something to remember. Any screen with a numeric field
//  gets `.keyboardDoneBar($focus)` and the escape hatch comes with it.
//

import SwiftUI

private struct KeyboardDoneBar: ViewModifier {
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            // Swiping the content is the gesture people try first, so it
            // works too rather than only the button.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus.wrappedValue = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(GG.Palette.violet300)
                }
            }
    }
}

extension View {
    /// Adds a Done button above the keyboard, for screens whose fields use a
    /// pad with no return key.
    ///
    /// Pair it with `.focused($focus)` on every numeric field — the button
    /// clears that focus, so a field it doesn't know about stays stuck.
    func keyboardDoneBar(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(KeyboardDoneBar(focus: focus))
    }
}
