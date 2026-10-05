import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

/// Role capability checks shared by screens. The backend enforces the same
/// matrix (requireRole on every route); these only decide what the UI shows.
/// The role → routes map lives in dashboard_shell.dart.

final currentRoleProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?['role'] as String?,
);

bool isAdminRole(String? role) => role == 'super_admin' || role == 'store_manager';

/// Settlements, profit, driver cash, deposits' fate — admin only.
bool canSeeSettlementMoney(String? role) => isAdminRole(role);

/// Item cost and sale prices. The purchaser enters them; the sorter and the
/// driver never see a price.
bool canSeePrices(String? role) => isAdminRole(role) || role == 'purchaser';

/// Create manifests, attach orders, dispatch, deliver/return, cash handover.
bool canManageInternalShipments(String? role) => isAdminRole(role);

/// Create / attach / receive / edit tracking on courier shipments.
bool canEditExternalShipments(String? role) => isAdminRole(role) || role == 'purchaser';

/// Bag labels and the manifest handover sheet.
bool canPrintLabels(String? role) => isAdminRole(role) || role == 'sorter';
