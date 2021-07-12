// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:scoped_model/scoped_model.dart';

import 'package:flutter_gallery/demo/shrine/colors.dart';
import 'package:flutter_gallery/demo/shrine/model/app_state_model.dart';
import 'package:flutter_gallery/demo/shrine/model/product.dart';

class CategoryMenuPage extends StatelessWidget {
  const CategoryMenuPage({
    Key? key,
    this.onCategoryTap,
  }) : super(key: key);

  final VoidCallback? onCategoryTap;

  Widget _buildCategory(Category category, BuildContext context) {
    final String categoryString = category.toString().replaceAll('Category.', '').toUpperCase();
    final ThemeData theme = Theme.of(context);
    return ScopedModelDescendant<AppStateModel>(
      builder: (BuildContext context, Widget? child, AppStateModel model) =>
          GestureDetector(
            onTap: () {
              model.setCategory(category);
              onCategoryTap?.call();
            },
            child: model.selectedCategory == category
              ? Column(
                  children: <Widget>[
                    const SizedBox(height: 16.0),
                    Text(
                      categoryString,
                      style: theme.textTheme.bodyText1,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14.0),
                    Container(
                      width: 70.0,
                      height: 2.0,
                      color: kShrinePink400,
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    categoryString,
                    style: theme.textTheme.bodyText1!.copyWith(
                      color: kShrineBrown900.withAlpha(153)
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.only(top: 40.0),
        color: kShrinePink100,
        child: ListView(
          children: Category.values.map((Category c) => _buildCategory(c, context)).toList(),
        ),
      ),
    );
  }
}
