// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderEditable;

import 'actions.dart';
import 'editable_text.dart';
import 'focus_manager.dart';
import 'framework.dart';

/// The recipient of a [TextEditingAction].
///
/// TextEditingActions will only be enabled when an implementer of this class is
/// focused.
///
/// See also:
///
///   * [EditableTextState], which implements this and is the most typical
///     target of a TextEditingAction.
abstract class TextEditingActionTarget {
  /// The renderer that handles [TextEditingAction]s.
  ///
  /// See also:
  ///
  /// * [EditableTextState.renderEditable], which overrides this.
  RenderEditable get renderEditable;
}

/// An [Action] related to editing text.
///
/// Enables itself only when a [TextEditingActionTarget], e.g. [EditableText],
/// is currently focused. The result of this is that when a
/// TextEditingActionTarget is not focused, it will fall through to any
/// non-TextEditingAction that handles the same shortcut. For example,
/// overriding the tab key in [Shortcuts] with a TextEditingAction will only
/// invoke your TextEditingAction when a TextEditingActionTarget is focused,
/// otherwise the default tab behavior will apply.
///
/// The currently focused TextEditingActionTarget is available in the [invoke]
/// method via [textEditingActionTarget].
///
/// See also:
///
///  * [CallbackAction], which is a similar Action type but unrelated to text
///    editing.
abstract class TextEditingAction<T extends Intent> extends ContextAction<T> {
  /// Returns the currently focused [TextEditingAction], or null if none is
  /// focused.
  @protected
  TextEditingActionTarget? get textEditingActionTarget {
    // If a TextEditingActionTarget is not focused, then ignore this action.
    if (primaryFocus?.context == null
        || primaryFocus!.context! is! StatefulElement
        || ((primaryFocus!.context! as StatefulElement).state is! TextEditingActionTarget)) {
      return null;
    }
    return (primaryFocus!.context! as StatefulElement).state as TextEditingActionTarget;
  }

  @override
  bool isEnabled(T intent) {
    // The Action is disabled if there is no focused TextEditingActionTarget.
    return textEditingActionTarget != null;
  }
}
