import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Every icon in the app, named by what it means. All come from one set
/// (Phosphor), so they share the same stroke, corners and proportions.
/// The `*On` variants are the filled forms for a selected tab.
abstract final class KIcons {
  // Tabs
  static const summary = PhosphorIconsRegular.squaresFour;
  static const summaryOn = PhosphorIconsFill.squaresFour;
  static const parties = PhosphorIconsRegular.bookOpenText;
  static const partiesOn = PhosphorIconsFill.bookOpenText;
  static const deals = PhosphorIconsRegular.arrowsLeftRight;
  static const dealsOn = PhosphorIconsBold.arrowsLeftRight;
  static const stock = PhosphorIconsRegular.package;
  static const stockOn = PhosphorIconsFill.package;
  static const expenses = PhosphorIconsRegular.receipt;
  static const expensesOn = PhosphorIconsFill.receipt;

  // Actions
  static const add = PhosphorIconsBold.plus;
  static const remove = PhosphorIconsBold.minus;
  static const close = PhosphorIconsRegular.x;
  static const check = PhosphorIconsBold.check;
  static const checkCircle = PhosphorIconsFill.checkCircle;
  static const edit = PhosphorIconsRegular.pencilSimple;
  static const more = PhosphorIconsBold.dotsThree;
  static const back = PhosphorIconsRegular.arrowLeft;
  static const forward = PhosphorIconsRegular.arrowRight;
  static const chevronDown = PhosphorIconsRegular.caretDown;
  static const chevronRight = PhosphorIconsRegular.caretRight;
  static const search = PhosphorIconsRegular.magnifyingGlass;
  static const searchEmpty = PhosphorIconsRegular.magnifyingGlassMinus;
  static const archive = PhosphorIconsRegular.archive;
  static const cancelled = PhosphorIconsRegular.prohibit;
  static const calendar = PhosphorIconsRegular.calendarBlank;

  // Money and goods
  static const purchase = PhosphorIconsRegular.trayArrowDown;
  static const sale = PhosphorIconsRegular.truck;
  static const commission = PhosphorIconsRegular.handshake;
  static const received = PhosphorIconsBold.arrowDownLeft;
  static const paid = PhosphorIconsBold.arrowUpRight;
  static const reversal = PhosphorIconsRegular.arrowCounterClockwise;
  static const adjustment = PhosphorIconsRegular.slidersHorizontal;
  static const history = PhosphorIconsRegular.clockCounterClockwise;
  static const cash = PhosphorIconsRegular.money;
  static const cloth = PhosphorIconsRegular.coatHanger;
  static const profitUp = PhosphorIconsBold.trendUp;
  static const profitDown = PhosphorIconsBold.trendDown;
  static const ledger = PhosphorIconsRegular.bookOpenText;

  // People and account
  static const people = PhosphorIconsRegular.users;
  static const addPerson = PhosphorIconsBold.userPlus;
  static const email = PhosphorIconsRegular.envelopeSimple;
  static const emailSent = PhosphorIconsRegular.envelopeOpen;
  static const send = PhosphorIconsBold.paperPlaneTilt;
  static const lock = PhosphorIconsRegular.lockSimple;
  static const key = PhosphorIconsRegular.key;
  static const shield = PhosphorIconsRegular.shieldCheck;
  static const show = PhosphorIconsRegular.eye;
  static const hide = PhosphorIconsRegular.eyeSlash;
  static const signIn = PhosphorIconsBold.signIn;
  static const signOut = PhosphorIconsRegular.signOut;
  static const language = PhosphorIconsRegular.translate;

  // States
  static const info = PhosphorIconsRegular.info;
  static const warning = PhosphorIconsRegular.warningCircle;
  static const offline = PhosphorIconsRegular.cloudSlash;
}
