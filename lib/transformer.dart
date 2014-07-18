library dartson.transformer;

import 'dart:async';
import 'dart:io';

import './dartson.dart';
import 'package:barback/barback.dart';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/src/generated/java_core.dart' show CharSequence;
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/parser.dart';
import 'package:analyzer/src/generated/scanner.dart';
import 'package:source_maps/refactor.dart';
import 'package:source_maps/span.dart' show SourceFile;

const SIMPLE_TYPES = const['String', 'num', 'bool', 'int', 'List', 'Map'];

class DartsonTransformer extends Transformer {

  DartsonTransformer();

  DartsonTransformer.asPlugin(BarbackSettings settings) :
    this();

  Future<bool> isPrimary(AssetId inputId) {
    if (inputId.extension != '.dart') {
      return new Future.value(false);
    }

    return new File(inputId.path).readAsString().then(
        (c) => c.contains("@DartsonEntity"));
  }

  Future apply(Transform transform) {

  }

  CompilationUnit _parseUnit(String code) {

  }
}

class FileCompiler extends _ErrorCollector {
  Parser parser;
  CharSequenceReader reader;
  Scanner scanner;
  CompilationUnit compilationUnit;
  List<ClassDeclaration> _entities = [];
  Editor editor;

  List<ClassDeclaration> get entities => _entities;

  FileCompiler(String path) {
    var code = new File(path).readAsStringSync();

    editor = new Editor(path, code);
    reader = new CharSequenceReader(code);
    scanner = new Scanner(null, reader, this);
    parser = new Parser(null, this);

    compilationUnit = parser.parseCompilationUnit(scanner.tokenize());
    _findDartsonEntities();
  }

  void _findDartsonEntities() {
    compilationUnit.declarations.forEach((m) {
      if (m is ClassDeclaration && m.metadata.any((n) => n.name.name == 'DartsonEntity')) {
        _entities.add(m);
      }
    });
  }

  Map<String, String> buildEntityMap(ClassDeclaration entity) {
    Map<String, String> resp = {};

    entity.members.forEach((ClassMember member) {
      if (member is FieldDeclaration) {
        DartsonProperty dartEnt = _getEntity(member.metadata);
        // run through all delegated variables
        member.fields.variables.forEach((VariableDeclaration d) {
          var jsonName = d.name.name;
          // fetch the correct name of the entity
          if (dartEnt != null && dartEnt.name != null && dartEnt.name.isNotEmpty) {
            jsonName = dartEnt.name;
          }

          if (dartEnt != null ? !dartEnt.ignore : true) {
            // check the type and get a serializable value
            resp[jsonName] = _isSimpleType(d) ? d.name.name : "${d.name.name}.toJson()";
          }
        });
      }
    });

    return resp;
  }

  String buildToJsonMethod(Map<String, String> entityMap) {
    String resp = "Map toJson() => {";
    List<String> props = [];
    entityMap.forEach((key, prop) {
      props.add('"${key}": ${prop}');
    });
    resp += props.join(',');
    resp += "};";

    return resp;
  }
}

bool _isSimpleType(VariableDeclaration d) {
  if (d.parent is VariableDeclarationList) {
    var type = d.parent.type as TypeName;
    var val = type.name.beginToken.value();
    return SIMPLE_TYPES.contains(val);
  } else {
    return false;
  }
}

DartsonProperty _getEntity(NodeList<Annotation> meta) {
  Annotation annotation = meta.firstWhere((m) => m.name.name == 'DartsonProperty', orElse: () => null);
  if (annotation != null) {
    var argsMap = {};
    annotation.arguments.arguments.forEach((arg) {
      if (arg is NamedExpression) {
        var name = arg.name.label.name;
        var value = arg.expression.value;

        argsMap[name] = value;
      }
    });
    return new DartsonProperty(ignore: argsMap['ignore'] == true, name: argsMap['name']);
  } else {
    return null;
  }
}

class Editor {
  SourceFile sourceFile;
  TextEditTransaction editor;

  Editor(String path, String code) {
    sourceFile = new SourceFile.text(path, code);
    editor = new TextEditTransaction(code, sourceFile);
  }
}

class _ErrorCollector extends AnalysisErrorListener {
  final errors = <AnalysisError>[];
  onError(err) => errors.add(err);
}
