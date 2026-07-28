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
import UIKit

private struct KeyboardDoneBar: ViewModifier {
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            // Swiping the content is the gesture people try first, so it
            // works too rather than only the button.
            .scrollDismissesKeyboard(.interactively)
            // Tapping a figure to correct it put the caret wherever the tap
            // landed — usually before the first digit, so clearing "1091.87"
            // meant six taps of a delete key that was deleting backwards
            // from the wrong end. Selecting the number on focus makes the
            // common case (replace it) one gesture, and the rare case
            // (amend it) one tap to deselect.
            //
            // Restricted to number pads on purpose: doing this to a name
            // field would wipe the name of anyone who tapped in to add a
            // surname.
            .onReceive(NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification
            )) { note in
                guard let field = note.object as? UITextField,
                      field.keyboardType == .decimalPad || field.keyboardType == .numberPad
                else { return }
                // A frame later: UIKit places the caret after this fires,
                // and would undo the selection.
                DispatchQueue.main.async { field.selectAll(nil) }
            }
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
