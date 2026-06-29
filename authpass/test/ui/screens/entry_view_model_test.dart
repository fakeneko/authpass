import 'dart:typed_data';

import 'package:authpass/bloc/app_data.dart';
import 'package:authpass/bloc/kdbx/file_content.dart';
import 'package:authpass/bloc/kdbx/file_source.dart';
import 'package:authpass/bloc/kdbx_bloc.dart';
import 'package:authpass/ui/screens/password_list.dart';
import 'package:authpass/utils/constants.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:mockito/mockito.dart';

import '../../util/test_util.dart';
import '../../util/test_util.mocks.dart';

void main() {
  PrintAppender.setupLogging();
  final testUtil = TestUtil();
  group('entry view model', () {
    late KdbxFile file;
    late KdbxEntry entry;
    late MockKdbxBloc kdbxBloc;

    setUp(() {
      file = testUtil.createFile();
      final rootGroup = file.body.rootGroup;
      entry = KdbxEntry.create(file, rootGroup);
      rootGroup.addEntry(entry);

      kdbxBloc = MockKdbxBloc();
      final fakeFile = OpenedFile(
        (b) => b
          ..lastOpenedAt = clock.now().toUtc()
          ..uuid = AppDataBloc.createUuid()
          ..sourceType = OpenedFilesSourceType.Url
          ..sourcePath = 'foo'
          ..name = 'bar',
      );
      final fakeKdbxOpenedFile = KdbxOpenedFile(
        fileSource: FileSourceUrl(
          Uri.parse('https://authpass.app/'),
          uuid: AppDataBloc.createUuid(),
        ),
        openedFile: fakeFile,
        kdbxFile: file,
        kdbxFileContent: FileContent(Uint8List(0)),
      );
      when(kdbxBloc.fileForKdbxFile(any)).thenReturn(fakeKdbxOpenedFile);
    });
    String? website(String value) {
      entry.setString(EntryViewModel.websiteKey, PlainValue(value));
      final vm = EntryViewModel(entry, kdbxBloc);
      return vm.website;
    }

    test('url transforms', () {
      // bloc.fileForFileSource()

      expect(website('authpass.app'), 'http://authpass.app/');
      // TODO we should probably fix this somehow.
      expect(website('authpass.app\nloremipsum'), 'http://authpass.app/');
      expect(website('\n\nauthpass.app\r\n'), 'http://authpass.app/');
      expect(website('\n\nauthpass.app//blubb\r\n'), 'http://authpass.app/');
      expect(website('   \n'), isNull);
    });

    test('entry directly in root group has empty groupNames', () {
      // The entry created in setUp lives directly under the root group. The
      // root container must be stripped from groupNames, so the breadcrumb is
      // empty and signals "no enclosing group" to both list and detail.
      final vm = EntryViewModel(entry, kdbxBloc);
      expect(vm.groupNames, isEmpty);
    });

    test('root entry display path falls back to the database name', () {
      // groupNames is empty for a root entry, so the shared display helper
      // shows the database / root group name instead of rendering nothing.
      final vm = EntryViewModel(entry, kdbxBloc);
      expect(vm.groupDisplayPath, file.body.meta.databaseName.get());
      expect(vm.groupDisplayPath, isNotEmpty);
    });

    test('null/blank group name is rendered without throwing', () {
      // A group whose name is null must not crash groupNames construction; the
      // level is preserved as an empty placeholder rather than throwing.
      final group = file.createGroup(
        parent: file.body.rootGroup,
        name: 'placeholder',
      );
      group.name.set(null);
      final blankEntry = KdbxEntry.create(file, group);
      group.addEntry(blankEntry);

      final vm = EntryViewModel(blankEntry, kdbxBloc);
      expect(() => vm.groupNames, returnsNormally);
      expect(vm.groupNames, [CharConstants.empty]);
      expect(() => vm.groupDisplayPath, returnsNormally);
    });

    test('nested groups produce a root-stripped breadcrumb', () {
      // Multi-level groups keep their hierarchy in order, with the root
      // container excluded by the unified rule.
      final work = file.createGroup(parent: file.body.rootGroup, name: 'Work');
      final email = file.createGroup(parent: work, name: 'Email');
      final nestedEntry = KdbxEntry.create(file, email);
      email.addEntry(nestedEntry);

      final vm = EntryViewModel(nestedEntry, kdbxBloc);
      expect(vm.groupNames, ['Work', 'Email']);
      expect(
        vm.groupDisplayPath,
        ['Work', 'Email'].join(CharConstants.chevronRight),
      );
    });
  });
}
