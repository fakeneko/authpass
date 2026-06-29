import 'dart:async';

import 'package:authpass/bloc/analytics.dart';
import 'package:authpass/bloc/kdbx_bloc.dart';
import 'package:authpass/l10n-generated/app_localizations.dart';
import 'package:authpass/ui/common_fields.dart';
import 'package:authpass/ui/screens/entry_details.dart';
import 'package:authpass/utils/base32utils.dart';
import 'package:authpass/utils/constants.dart';
import 'package:authpass/utils/extension_methods.dart';
import 'package:authpass/utils/otpauth.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kdbx/kdbx.dart';
import 'package:logging/logging.dart';
import 'package:otp/otp.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

final _logger = Logger('totp_list');

class TotpListScreen extends StatelessWidget {
  const TotpListScreen({super.key});

  static const routeSettings = RouteSettings(name: '/totpList');

  static Route<void> route() => MaterialPageRoute(
    settings: routeSettings,
    builder: (context) => const TotpListScreen(),
  );

  @override
  Widget build(BuildContext context) {
    final kdbxBloc = Provider.of<KdbxBloc>(context);
    final streams = kdbxBloc.openedFilesKdbx.map(
      (file) => file.dirtyObjectsChanged,
    );
    if (streams.isEmpty) {
      final loc = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(loc.totpListTitle)),
        body: Center(
          child: Text(loc.totpListNoFilesOpen),
        ),
      );
    }
    return StreamBuilder<bool>(
      stream: Rx.merge(streams).map((x) => true),
      builder: (context, snapshot) {
        return TotpListContent(
          kdbxBloc: kdbxBloc,
          openedKdbxFiles: kdbxBloc.openedFilesKdbx,
        );
      },
    );
  }
}

class TotpListContent extends StatefulWidget {
  const TotpListContent({
    super.key,
    required this.kdbxBloc,
    required this.openedKdbxFiles,
  });

  final KdbxBloc kdbxBloc;
  final List<KdbxFile> openedKdbxFiles;

  @override
  _TotpListContentState createState() => _TotpListContentState();
}

class _TotpListContentState extends State<TotpListContent> {
  Timer? _timer;
  List<TotpEntryViewModel>? _totpEntries;

  @override
  void initState() {
    super.initState();
    _updateTotpEntries();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant TotpListContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openedKdbxFiles != widget.openedKdbxFiles) {
      _updateTotpEntries();
    }
  }

  void _updateTotpEntries() {
    final entries = <TotpEntryViewModel>[];
    final commonFields = CommonFields(AppLocalizations.of(context));
    for (final file in widget.openedKdbxFiles) {
      for (final entry in file.body.rootGroup.getAllEntries()) {
        final otpValue = _findOtpValue(entry, commonFields);
        if (otpValue != null) {
          try {
            final otpAuth = _parseOtpAuth(otpValue, entry, commonFields);
            if (otpAuth != null) {
              entries.add(TotpEntryViewModel(
                entry: entry,
                otpAuth: otpAuth,
                kdbxBloc: widget.kdbxBloc,
              ));
            }
          } catch (e, stackTrace) {
            _logger.fine('Error parsing OTP for ${entry.label}', e, stackTrace);
          }
        }
      }
    }
    entries.sort((a, b) => a.label.compareTo(b.label));
    setState(() {
      _totpEntries = entries;
    });
  }

  String? _findOtpValue(KdbxEntry entry, CommonFields commonFields) {
    // Check all known OTP field keys
    for (final field in [
      commonFields.otpAuth,
      commonFields.otpAuthCompat2,
      commonFields.otpAuthCompat1,
    ]) {
      final value = entry.getString(field.key)?.getText();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  OtpAuth? _parseOtpAuth(
    String value,
    KdbxEntry entry,
    CommonFields commonFields,
  ) {
    if (value.startsWith(OtpAuth.URI_PREFIX)) {
      return OtpAuth.fromUri(Uri.parse(value));
    }
    final otpAuth = OtpAuth.fromQueryString(value);
    if (otpAuth != null) {
      return otpAuth;
    }
    try {
      final binarySecret = base32Decode(value);
      final settings =
          commonFields.otpAuthCompat1Settings.stringValue(entry) ??
          CharConstants.empty;
      final settingsOptions = settings.isEmpty
          ? <String>[]
          : settings.split(CharConstants.semiColon);
      return OtpAuth(
        secret: binarySecret,
        period: settingsOptions.optGet(0)?.toInt() ?? OtpAuth.DEFAULT_PERIOD,
        digits: settingsOptions.optGet(1)?.toInt() ?? OtpAuth.DEFAULT_DIGITS,
      );
    } on FormatException {
      // ignore
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return _totpEntries == null || _totpEntries!.isEmpty
        ? Center(
            child: Text(loc.totpListEmpty),
          )
        : ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _totpEntries!.length,
            itemBuilder: (context, index) {
              final vm = _totpEntries![index];
              return _TotpListTile(
                viewModel: vm,
                onTap: () {
                  Navigator.of(context).push(
                    EntryDetailsScreen.route(entry: vm.entry),
                  );
                },
              );
            },
          );
  }
}

class TotpEntryViewModel {
  TotpEntryViewModel({
    required this.entry,
    required this.otpAuth,
    required this.kdbxBloc,
  }) : label = entry.label ?? CharConstants.empty;

  final KdbxEntry entry;
  final OtpAuth otpAuth;
  final KdbxBloc kdbxBloc;
  final String label;

  String? _currentCode;
  int? _elapsed;
  int? _period;

  String get currentCode {
    _updateCode();
    return _currentCode ?? CharConstants.empty;
  }

  int get elapsed {
    _updateCode();
    return _elapsed ?? 0;
  }

  int get remainingSeconds {
    _updateCode();
    return _period! - _elapsed!;
  }

  void _updateCode() {
    final now = clock.now().millisecondsSinceEpoch;
    final secretBase32 = base32Encode(otpAuth.secret);
    _currentCode = OTP.generateTOTPCodeString(
      secretBase32,
      now,
      algorithm: otpAuth.algorithm,
      length: otpAuth.digits,
      interval: otpAuth.period,
      isGoogle: true,
    );
    _elapsed = (now ~/ 1000) % otpAuth.period;
    _period = otpAuth.period;
  }
}

class _TotpListTile extends StatelessWidget {
  const _TotpListTile({
    required this.viewModel,
    this.onTap,
  });

  final TotpEntryViewModel viewModel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final remaining = viewModel.remainingSeconds;
    final isUrgent = remaining <= 5;
    final progressColor = isUrgent ? Colors.red : Colors.green;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircularPercentIndicator(
          radius: 20.0,
          lineWidth: 4,
          percent: 1 - (viewModel.elapsed / viewModel.period.toDouble()),
          backgroundColor: Colors.black12,
          progressColor: progressColor,
          center: Text(
            '$remaining',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: progressColor,
            ),
          ),
        ),
        title: Text(viewModel.label),
        subtitle: Text(
          viewModel.currentCode,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'JetBrainsMono',
                letterSpacing: 2,
              ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: loc.totpListCopyCode,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: viewModel.currentCode));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc.totpListCodeCopied(viewModel.currentCode)),
                duration: const Duration(seconds: 2),
              ),
            );
            Provider.of<Analytics>(context, listen: false)
                .events
                .trackCopyField(key: 'totp'); // NON-NLS
          },
        ),
        onTap: onTap,
      ),
    );
  }
}
