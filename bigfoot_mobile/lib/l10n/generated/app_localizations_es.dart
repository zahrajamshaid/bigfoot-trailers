// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Bigfoot Trailers';

  @override
  String get appTitleShort => 'Bigfoot';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonLoading => 'Cargando';

  @override
  String get commonDismiss => 'Descartar';

  @override
  String get commonUnknown => 'Desconocido';

  @override
  String get commonUser => 'Usuario';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonYes => 'Sí';

  @override
  String get commonNo => 'No';

  @override
  String get commonNone => 'Ninguno';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonAdd => 'Agregar';

  @override
  String get commonSet => 'Establecer';

  @override
  String get commonUndo => 'Deshacer';

  @override
  String commonFailed(String msg) {
    return 'Error: $msg';
  }

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonSubmit => 'Enviar';

  @override
  String get commonEdit => 'Editar';

  @override
  String get commonOk => 'OK';

  @override
  String get navDashboard => 'Panel';

  @override
  String get navTrailers => 'Remolques';

  @override
  String get navProduction => 'Producción';

  @override
  String get navQc => 'Control de Calidad';

  @override
  String get navPayroll => 'Nómina';

  @override
  String get navDeliveries => 'Entregas';

  @override
  String get navAdmin => 'Administración';

  @override
  String get navMyQueue => 'Mi Cola';

  @override
  String get navMyPoints => 'Mis Puntos';

  @override
  String get navMyDeliveries => 'Mis Entregas';

  @override
  String get connectionConnected => 'Conectado';

  @override
  String get connectionConnecting => 'Conectando';

  @override
  String get connectionOffline => 'Sin conexión';

  @override
  String get offlineBanner =>
      'Sin conexión - actualizaciones en tiempo real pausadas';

  @override
  String get backToExit => 'Presione atrás de nuevo para salir';

  @override
  String get loginTitle => 'BIGFOOT TRAILERS';

  @override
  String get loginSubtitle => 'Inicie sesión para continuar';

  @override
  String get loginEmail => 'Correo electrónico';

  @override
  String get loginPassword => 'Contraseña';

  @override
  String get loginRememberEmail => 'Recordar correo';

  @override
  String get loginSignIn => 'Iniciar sesión';

  @override
  String get loginPasswordRequired => 'Por favor ingrese su contraseña';

  @override
  String get settingsConnectionSection => 'CONEXIÓN';

  @override
  String get settingsSecuritySection => 'SEGURIDAD';

  @override
  String get settingsAboutSection => 'ACERCA DE';

  @override
  String get settingsLanguageSection => 'IDIOMA';

  @override
  String get settingsWebSocketStatus => 'Estado de WebSocket';

  @override
  String get settingsWebSocketSubtitle => 'Conexión en tiempo real';

  @override
  String get settingsPinTitle => 'Requerir PIN al abrir la app';

  @override
  String get settingsPinEnabled => 'Bloqueo PIN activado';

  @override
  String get settingsPinDisabled => 'No se requiere PIN';

  @override
  String get settingsPinSetTitle => 'Defina un PIN de 4 dígitos';

  @override
  String get settingsPinSetSubtitle =>
      'Se le pedirá este PIN cada vez que abra la app.';

  @override
  String get settingsPinConfirmTitle => 'Confirmar PIN';

  @override
  String get settingsPinConfirmSubtitle =>
      'Vuelva a ingresar su PIN para confirmar.';

  @override
  String get settingsPinMismatch => 'Los PIN no coinciden. Intente de nuevo.';

  @override
  String get settingsPinDisableTitle => 'Desactivar bloqueo PIN';

  @override
  String get settingsPinDisableSubtitle =>
      'Ingrese su PIN actual para desactivar el bloqueo.';

  @override
  String get settingsPinCancel => 'Cancelar';

  @override
  String get settingsAppVersion => 'Versión de la app';

  @override
  String get settingsApiVersion => 'Versión de la API';

  @override
  String get settingsLanguageTitle => 'Idioma de la app';

  @override
  String get settingsLanguageEnglish => 'Inglés';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsSignOut => 'Cerrar sesión';

  @override
  String get settingsSignOutConfirmTitle => 'Cerrar sesión';

  @override
  String get settingsSignOutConfirmMessage =>
      '¿Está seguro de que desea cerrar sesión? Deberá iniciar sesión nuevamente.';

  @override
  String get dashboardGoodMorning => 'Buenos días';

  @override
  String get dashboardGoodAfternoon => 'Buenas tardes';

  @override
  String get dashboardGoodEvening => 'Buenas noches';

  @override
  String get authPinTitle => 'Ingrese su PIN';

  @override
  String get authPinSubtitle => 'Ingrese su PIN de 4 dígitos para desbloquear';

  @override
  String get authPinIncorrect => 'PIN incorrecto';

  @override
  String get authPinSignOut => 'Cerrar sesión';

  @override
  String get authSplashTagline =>
      'Construido para transportar. Listo para mover.';

  @override
  String get dashStatActiveTrailers => 'Remolques activos';

  @override
  String get dashStatReadyForDelivery => 'Listos para entrega';

  @override
  String get dashStatHotTrailers => 'Remolques urgentes';

  @override
  String get dashStatHotBadge => 'URGENTE';

  @override
  String get dashStatStalledSteps => 'Pasos detenidos';

  @override
  String get dashStatCompletedThisWeek => 'Completados esta semana';

  @override
  String get dashStatQcFailRate => 'Tasa de fallas QC';

  @override
  String get dashStatPointsToday => 'Puntos de hoy';

  @override
  String get dashStatPointsThisWeek => 'Puntos de la semana';

  @override
  String get dashStatNextTrailer => 'Próximo remolque';

  @override
  String get dashStatReadyForInspection => 'Listo para inspección';

  @override
  String get dashStatInspectionsToday => 'Inspecciones de hoy';

  @override
  String get dashStatFailRateToday => 'Tasa de fallas hoy';

  @override
  String get dashStatReworkQueue => 'Cola de retrabajo';

  @override
  String get dashStatScheduled => 'Programadas';

  @override
  String get dashStatReadyForPickup => 'Listos para recoger';

  @override
  String get dashStockInventory => 'Inventario de stock';

  @override
  String get statusPending => 'Pendiente';

  @override
  String get statusInProduction => 'En producción';

  @override
  String get statusReady => 'Listo';

  @override
  String get statusInTransit => 'En tránsito';

  @override
  String get statusDelivered => 'Entregado';

  @override
  String get statusOnHold => 'En espera';

  @override
  String get statusScheduled => 'Programada';

  @override
  String get statusFailed => 'Fallida';

  @override
  String get statusWaiting => 'Esperando';

  @override
  String get statusActive => 'Activo';

  @override
  String get statusComplete => 'Completo';

  @override
  String get statusRework => 'Retrabajo';

  @override
  String get saleStatusSold => 'VENDIDO';

  @override
  String get saleStatusSalePending => 'VENTA PENDIENTE';

  @override
  String get saleStatusAvailable => 'Disponible';

  @override
  String get saleStatusSoldLong => 'Vendido';

  @override
  String get saleStatusSalePendingLong => 'Venta pendiente';

  @override
  String get trailersSearchHint => 'Buscar por SO# o cliente...';

  @override
  String get trailersFilterHotOnly => 'Solo urgentes';

  @override
  String get trailersStockBuild => 'Construcción de stock';

  @override
  String get trailersEmpty => 'No se encontraron remolques';

  @override
  String trailersStepIndicator(int step, int total, String dept) {
    return 'Paso $step/$total — $dept';
  }

  @override
  String get cacheBannerJustNow => 'ahora mismo';

  @override
  String get cacheBannerUnknownTime => 'hora desconocida';

  @override
  String cacheBannerMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'hace $minutes minutos',
      one: 'hace 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String cacheBannerMessage(String when) {
    return 'Mostrando datos en caché. Última actualización $when.';
  }

  @override
  String get createTrailerTitle => 'Crear remolque';

  @override
  String get createTrailerSubmit => 'Crear remolque';

  @override
  String get createTrailerModelsEmpty =>
      'No hay modelos de remolque configurados en el servidor.';

  @override
  String get createTrailerModelsLoadFail =>
      'No se pudieron cargar los modelos. Verifique su conexión.';

  @override
  String get createTrailerModelsNone =>
      'No hay modelos de remolque disponibles.';

  @override
  String createTrailerModelFallback(String id) {
    return 'Modelo $id';
  }

  @override
  String get createTrailerPickPdfFail => 'No se pudo leer el PDF seleccionado.';

  @override
  String get createTrailerPickerOpenFail =>
      'No se pudo abrir el selector de archivos.';

  @override
  String get createTrailerStockDestRequired => 'Seleccione un destino de stock';

  @override
  String createTrailerCreated(String so) {
    return 'Remolque $so creado con 12 pasos del flujo';
  }

  @override
  String createTrailerCreatedPdfWarn(String warning) {
    return 'Remolque creado. La carga del PDF falló: $warning';
  }

  @override
  String get createTrailerFail => 'Error al crear el remolque';

  @override
  String get createTrailerPdfRetryLater =>
      'sin conexión — el PDF se reintentará luego';

  @override
  String get createTrailerSoLabel => 'Número de SO *';

  @override
  String get createTrailerSoRequired => 'El número de SO es obligatorio';

  @override
  String get createTrailerModelLabel => 'Modelo de remolque *';

  @override
  String get createTrailerModelRequired => 'Seleccione un modelo';

  @override
  String get createTrailerColorLabel => 'Color';

  @override
  String get createTrailerSizeLabel => 'Tamaño (ft)';

  @override
  String get createTrailerNotesLabel => 'Opciones / Notas';

  @override
  String get createTrailerSpecialLabel => 'Nota especial';

  @override
  String get createTrailerSpecialHint => 'ej. enviar vacío, retener por VIN';

  @override
  String get createTrailerStockBuild => 'Construcción de stock';

  @override
  String get createTrailerStockBuildSubtitle => 'Sin cliente asignado';

  @override
  String get createTrailerCustomerLabel => 'Cliente';

  @override
  String get createTrailerCustomerHint =>
      'Nombre del comprador — dejar en blanco para stock';

  @override
  String get createTrailerCustomerHelper =>
      'Opcional. Un remolque con cliente se marca como vendido.';

  @override
  String get createTrailerStockDestLabel => 'Destino de stock *';

  @override
  String get createTrailerPdfSectionTitle => 'PDF de orden de venta QB';

  @override
  String get createTrailerPdfRemoveTooltip => 'Quitar PDF';

  @override
  String get createTrailerPdfOptionalHelper =>
      'Opcional — adjunte el PDF de orden de venta de QuickBooks.';

  @override
  String get createTrailerPdfReplace => 'Reemplazar PDF';

  @override
  String get createTrailerPdfAttach => 'Adjuntar PDF';

  @override
  String editTrailerTitle(String so) {
    return 'Editar $so';
  }

  @override
  String get editTrailerSubmit => 'Guardar cambios';

  @override
  String editTrailerUpdated(String so) {
    return 'Remolque $so actualizado';
  }

  @override
  String editTrailerUpdatedPdfWarn(String warning) {
    return 'Remolque actualizado. La carga del PDF falló: $warning';
  }

  @override
  String get editTrailerFail => 'Error al actualizar el remolque';

  @override
  String get editTrailerPdfDiscardTooltip => 'Descartar nuevo PDF';

  @override
  String get editTrailerPdfExisting =>
      'Ya hay un PDF adjunto. Seleccione un archivo nuevo para reemplazarlo.';

  @override
  String trailerDetailTitleFallback(int id) {
    return 'Remolque #$id';
  }

  @override
  String get trailerDetailMenuEdit => 'Editar remolque';

  @override
  String get trailerDetailMenuRemoveHot => 'Quitar urgente';

  @override
  String get trailerDetailMenuMarkHot => 'Marcar urgente';

  @override
  String get trailerDetailMenuSetPriority => 'Establecer prioridad';

  @override
  String get trailerDetailMenuAddAddon => 'Agregar accesorio';

  @override
  String get trailerDetailMenuViewPdf => 'Ver PDF QB';

  @override
  String get trailerDetailMenuDelete => 'Eliminar remolque';

  @override
  String get trailerDetailTabInfo => 'Información';

  @override
  String get trailerDetailTabWorkflow => 'Flujo';

  @override
  String get trailerDetailTabHistory => 'Historial';

  @override
  String get trailerDetailTabPhotos => 'Fotos';

  @override
  String get trailerDetailDeleteTitle => '¿Eliminar remolque?';

  @override
  String trailerDetailDeleteBody(String so) {
    return 'Esto elimina permanentemente $so y TODOS los registros relacionados — pasos de producción, inspecciones de QC, entregas, fotos, accesorios e historial.\n\nNo se puede deshacer.';
  }

  @override
  String get trailerDetailDeleteConfirm => 'Eliminar';

  @override
  String trailerDetailDeleted(String so) {
    return '$so eliminado';
  }

  @override
  String trailerDetailDeleteFailed(String msg) {
    return 'Error al eliminar: $msg';
  }

  @override
  String get trailerDetailPriorityTitle => 'Establecer prioridad';

  @override
  String get trailerDetailPriorityLabel => 'Número de prioridad';

  @override
  String get trailerDetailPriorityHint => '1 = más alta';

  @override
  String get trailerDetailPrioritySet => 'Establecer';

  @override
  String get trailerDetailAddonTitle => 'Agregar accesorio';

  @override
  String get trailerDetailAddonName => 'Nombre del accesorio *';

  @override
  String get trailerDetailAddonNotes => 'Notas';

  @override
  String get trailerDetailAddonAdd => 'Agregar';

  @override
  String trailerDetailUpdateFailed(String msg) {
    return 'Error al actualizar: $msg';
  }

  @override
  String get trailerDetailMarkedSold => 'Remolque marcado como vendido';

  @override
  String get trailerDetailMarkedSalePending =>
      'Remolque marcado como venta pendiente';

  @override
  String get trailerDetailMarkedAvailable => 'Remolque marcado como disponible';

  @override
  String get trailerDetailBannerSold => 'VENDIDO';

  @override
  String get trailerDetailBannerSalePending => 'VENTA PENDIENTE';

  @override
  String get trailerDetailBannerAvailable => 'DISPONIBLE';

  @override
  String trailerDetailSoldTo(String buyer) {
    return 'Vendido a $buyer';
  }

  @override
  String get trailerDetailMarkedSoldShort => 'Marcado como vendido';

  @override
  String get trailerDetailSalePendingDesc =>
      'Una venta está en curso para este remolque';

  @override
  String get trailerDetailAvailableDesc =>
      'Aún no se ha vendido — disponible para un cliente';

  @override
  String get trailerDetailMarkAvailable => 'Marcar disponible';

  @override
  String get trailerDetailAvailable => 'Disponible';

  @override
  String get trailerDetailSalePending => 'Venta pendiente';

  @override
  String get trailerDetailSold => 'Vendido';

  @override
  String trailerDetailMarkSoldTitle(String so) {
    return 'Marcar $so como vendido';
  }

  @override
  String get trailerDetailMarkSoldBuyerRequired =>
      'Ingrese el nombre del comprador';

  @override
  String get trailerDetailMarkSoldBuyerLabel => 'Nombre del comprador *';

  @override
  String get trailerDetailMarkSoldBuyerHint => '¿Quién compró este remolque?';

  @override
  String get trailerDetailMarkSoldButton => 'Marcar vendido';

  @override
  String get trailerDetailUnknownModel => 'Modelo desconocido';

  @override
  String get trailerDetailNoCustomer => 'Ninguno';

  @override
  String get trailerDetailFieldCustomer => 'Cliente';

  @override
  String get trailerDetailFieldColor => 'Color';

  @override
  String get trailerDetailFieldSize => 'Tamaño';

  @override
  String get trailerDetailFieldPriority => 'Prioridad';

  @override
  String get trailerDetailPriorityDefault => 'Por defecto';

  @override
  String get trailerDetailOpenPdf => 'Abrir PDF QB';

  @override
  String get trailerDetailNotesLabel => 'Opciones / Notas';

  @override
  String get trailerDetailSpecialLabel => 'Nota especial';

  @override
  String get trailerDetailAddonsTitle => 'Accesorios';

  @override
  String get trailerDetailDepartmentLabel => 'Departamento';

  @override
  String get trailerDetailLocationLabel => 'Ubicación';

  @override
  String get trailerDetailStatusReadyForDelivery => 'Listo para entrega';

  @override
  String get trailerDetailStatusInTransit => 'En tránsito';

  @override
  String get trailerDetailStatusDelivered => 'Entregado';

  @override
  String get trailerDetailStatusOnHold => 'En espera';

  @override
  String get trailerDetailStatusPendingProduction => 'Producción pendiente';

  @override
  String get trailerDetailStatusWorkflowComplete => 'Flujo completo';

  @override
  String get trailerDetailNoSteps => 'No hay pasos del flujo';

  @override
  String trailerDetailJumpTitle(int n) {
    return '¿Mover remolque al paso $n?';
  }

  @override
  String trailerDetailJumpBody(String dept) {
    return 'Esto coloca el remolque en \"$dept\" como paso activo actual.\n\n• Los pasos anteriores se marcarán como completados (no se otorgarán puntos por los no realizados).\n• Los pasos posteriores se reiniciarán a esperando.\n• Cada paso revertido se registra en la pestaña de historial.';
  }

  @override
  String get trailerDetailJumpReasonLabel => 'Motivo (opcional)';

  @override
  String get trailerDetailJumpReasonHint => 'ej. paso equivocado tocado antes';

  @override
  String get trailerDetailJumpConfirm => 'Mover aquí';

  @override
  String trailerDetailJumpedTo(String dept) {
    return 'Remolque movido a \"$dept\"';
  }

  @override
  String trailerDetailJumpFailed(String msg) {
    return 'Error al mover: $msg';
  }

  @override
  String get trailerDetailCurrentlyActive => 'Activo actualmente';

  @override
  String get trailerDetailMoveBackHere => 'Mover remolque atrás aquí';

  @override
  String get trailerDetailMoveHere => 'Mover remolque aquí';

  @override
  String get trailerDetailNoHistory => 'Sin historial todavía';

  @override
  String get trailerDetailNoPhotos => 'No hay fotos de etapas disponibles';

  @override
  String trailerDetailReworkBadge(int count) {
    return 'RETRABAJO x$count';
  }

  @override
  String trailerDetailCompletedOn(String when) {
    return 'Completado $when';
  }

  @override
  String trailerDetailPointsAwarded(String pts) {
    return '+$pts pts';
  }

  @override
  String trailerDetailStepLabel(int n) {
    return 'Paso $n';
  }

  @override
  String trailerDetailPriorityBadge(int n) {
    return '#$n';
  }

  @override
  String get queueLoading => 'Cargando cola...';

  @override
  String get queueDepartmentLabel => 'Departamento';

  @override
  String get queueTitleFallback => 'Cola';

  @override
  String get queueFilterStalled => 'Detenidos';

  @override
  String queueFilterStalledCount(int n) {
    return 'Detenidos ($n)';
  }

  @override
  String queueTrailerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remolques',
      one: '1 remolque',
    );
    return '$_temp0';
  }

  @override
  String get queueUndoTitle => '¿Deshacer finalización?';

  @override
  String get queueUndoBody =>
      'Esto devolverá el remolque a la cola de este departamento.';

  @override
  String get queueReversed => 'Paso revertido correctamente';

  @override
  String queueReverseFailed(String msg) {
    return 'Error al revertir: $msg';
  }

  @override
  String get queueEmptyTitle => 'Cola vacía';

  @override
  String get queueEmptyBody =>
      'No hay remolques esperando en este departamento';

  @override
  String get queueNoStalledTitle => 'Sin remolques detenidos';

  @override
  String get queueNoStalledBody =>
      'Nada en este departamento está por encima del umbral.\nDesactive el filtro \"Detenidos\" para ver la cola completa.';

  @override
  String get queueOpenDetailTooltip => 'Abrir detalle del remolque';

  @override
  String get queueCompleteButton => 'COMPLETAR';

  @override
  String queueMinutesInQueue(int n) {
    return '${n}m en cola';
  }

  @override
  String queueHoursInQueue(String n) {
    return '${n}h en cola';
  }

  @override
  String queueDaysHoursInQueue(int d, int h) {
    return '${d}d ${h}h en cola';
  }

  @override
  String queueReworkBadge(int count) {
    return 'RETRABAJO ×$count';
  }

  @override
  String queueOverlayPoints(String pts) {
    return '+$pts puntos';
  }

  @override
  String get queueOverlayRework => 'Completado (retrabajo)';

  @override
  String queueOverlayNext(String dept) {
    return 'Siguiente: $dept';
  }

  @override
  String get stepCompleteTitle => 'Completar paso';

  @override
  String get stepChecklistRequired =>
      'Responda cada elemento de la lista. Las notas son obligatorias en cualquier \"No\".';

  @override
  String stepChecklistLoadFail(String msg) {
    return 'Error al cargar la lista: $msg';
  }

  @override
  String get stepHotBadge => 'URGENTE';

  @override
  String get stepDetailModel => 'Modelo';

  @override
  String get stepDetailCustomer => 'Cliente';

  @override
  String get stepDetailColor => 'Color';

  @override
  String get stepDetailSize => 'Tamaño';

  @override
  String get stepDetailNotes => 'Notas';

  @override
  String stepPdfTitle(String so) {
    return '$so — Orden de venta QB';
  }

  @override
  String get stepViewQbPdf => 'Ver orden de venta QB';

  @override
  String get stepFullDetails => 'Detalles completos';

  @override
  String get stepViewFullDetails => 'Ver detalles completos del remolque';

  @override
  String stepReworkHeader(int count) {
    return 'RETRABAJO — Notas de fallas QC (×$count)';
  }

  @override
  String get stepReworkWarning => 'Los pasos de retrabajo otorgan 0 puntos.';

  @override
  String get stepSelfCheckTitle => 'Auto-verificación';

  @override
  String get stepSelfCheckHint =>
      'Confirme cada elemento antes de completar. Notas obligatorias en cualquier \"No\".';

  @override
  String get stepNoteRequired => 'Nota (obligatorio)';

  @override
  String get stepNotesLabel => 'Notas de finalización (opcional)';

  @override
  String get stepNotesHint => 'Notas sobre este paso...';

  @override
  String get stepCompleting => 'Completando...';

  @override
  String get stepCompleteCta => 'COMPLETAR PASO';

  @override
  String get stepCompleteSuccessTitle => '¡Paso completado!';

  @override
  String get stepReworkSuccessPoints => 'Retrabajo — 0 puntos';

  @override
  String stepNextDept(String dept) {
    return 'Siguiente → $dept';
  }

  @override
  String get allQueuesTitle => 'Todas las colas';

  @override
  String get allQueuesLoadFail => 'Error al cargar las colas';

  @override
  String get allQueuesReorderFail => 'Error al reordenar la cola';

  @override
  String get allQueuesEmpty => 'Cola vacía';

  @override
  String get qcFilterRework => 'Retrabajo';

  @override
  String qcReadyToInspect(int n) {
    return '$n listos para inspeccionar';
  }

  @override
  String qcInspectionsPending(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n inspecciones pendientes',
      one: '1 inspección pendiente',
    );
    return '$_temp0';
  }

  @override
  String get qcNoReworkTitle => 'Sin elementos de retrabajo';

  @override
  String get qcNoInspectionsTitle => 'Nada que inspeccionar';

  @override
  String get qcNoReworkBody => 'No hay inspecciones de retrabajo en la cola.';

  @override
  String get qcAllInspectedBody =>
      'Todas las inspecciones listas están terminadas.';

  @override
  String get qcQueuesClearBody => 'Todas las colas de QC están despejadas.';

  @override
  String get qcEarlierStageFallback => 'una etapa anterior';

  @override
  String qcStillAtStage(String so, String stage, String dept) {
    return '$so aún está en $stage. Inspeccione cuando llegue a $dept.';
  }

  @override
  String qcReadyCount(int n) {
    return '$n listo';
  }

  @override
  String qcUpcomingCount(int n) {
    return '· $n próximos';
  }

  @override
  String qcCurrentlyAt(String name) {
    return 'Actualmente en: $name';
  }

  @override
  String get qcUpcomingChip => 'PRÓXIMO';

  @override
  String get qcAnswerAll => 'Por favor responda todos los elementos';

  @override
  String get qcFillRequired =>
      'Por favor complete todos los campos obligatorios';

  @override
  String qcInspectTitle(String so) {
    return 'Inspeccionar $so';
  }

  @override
  String get qcSubmittingInspection => 'Enviando inspección...';

  @override
  String get qcStep1Title => 'Paso 1: Fotos';

  @override
  String get qcStep1Subtitle => 'Las fotos son opcionales';

  @override
  String get qcStep1PendingUploads =>
      'Espere a que terminen las cargas pendientes antes de continuar';

  @override
  String get qcInspectionPhotos => 'Fotos de inspección QC';

  @override
  String get qcNextChecklist => 'Siguiente: Lista';

  @override
  String get qcStep2Title => 'Paso 2: Lista de verificación';

  @override
  String get qcChecklistNotConfigured =>
      'No hay elementos configurados para este departamento';

  @override
  String get qcChecklistLoadFail => 'No se pudo cargar la lista';

  @override
  String get qcNextResult => 'Siguiente: Resultado';

  @override
  String qcAnsweredOf(int n, int total) {
    return '$n de $total';
  }

  @override
  String get qcOptionalNote => 'Nota opcional...';

  @override
  String get qcPass => 'PASA';

  @override
  String get qcFail => 'FALLA';

  @override
  String get qcWorker => 'Trabajador';

  @override
  String qcUpstreamMarkedPrefix(String who, String dept) {
    return '$who$dept marcó ';
  }

  @override
  String qcUpstreamFailedCount(int f, int t) {
    return 'Auto-verificaciones previas: $f fallaron de $t';
  }

  @override
  String qcUpstreamAllPassed(int n) {
    return 'Las $n auto-verificaciones previas pasaron';
  }

  @override
  String get qcStep3Title => 'Paso 3: Resultado de inspección';

  @override
  String get qcStep3Subtitle => 'Seleccione el resultado final de inspección';

  @override
  String get qcFinalQcWarning =>
      'QC FINAL — Aprobar marcará el remolque como Listo para entrega';

  @override
  String get qcSubmitInspection => 'Enviar inspección';

  @override
  String get qcNextFailDetails => 'Siguiente: Detalles de falla';

  @override
  String get qcStep4Title => 'Paso 4: Detalles de falla';

  @override
  String get qcStep4Subtitle =>
      'Describa el defecto y seleccione el departamento de retrabajo';

  @override
  String get qcFailNotesLabel => 'Notas de falla *';

  @override
  String get qcFailNotesHint => 'Describa qué falló y necesita corrección...';

  @override
  String get qcReworkTargetLabel => 'Departamento de retrabajo *';

  @override
  String get qcSelectDept => 'Seleccione departamento...';

  @override
  String qcInsertedAtPriorityOne(String dept) {
    return 'Este remolque se insertará con prioridad #1 en la cola de $dept';
  }

  @override
  String get qcTheSelectedDept => 'el departamento seleccionado';

  @override
  String get qcResultPassed => 'QC APROBADO';

  @override
  String get qcResultFailed => 'QC FALLIDO';

  @override
  String get qcReadyForDelivery => '¡Remolque listo para entrega!';

  @override
  String get qcSmsSent => 'SMS enviado';

  @override
  String get qcSendSms => 'Enviar SMS al cliente';

  @override
  String get qcCustomerSmsSent => 'SMS al cliente enviado';

  @override
  String qcSmsFailed(String msg) {
    return 'SMS falló: $msg';
  }

  @override
  String get qcSmsFailedRetry => 'SMS falló — reintente por favor';

  @override
  String qcReworkSentTo(String dept, int pos) {
    return 'Retrabajo enviado a $dept con prioridad #$pos';
  }

  @override
  String get qcManagersNotified =>
      'Los gerentes de producción han sido notificados';

  @override
  String get qcInspectionLoadFail => 'Error al cargar la inspección';

  @override
  String qcInspectionTitle(int id) {
    return 'Inspección #$id';
  }

  @override
  String get qcStatusPassed => 'APROBADO';

  @override
  String get qcStatusFailed => 'FALLIDO';

  @override
  String qcAttemptNumber(int n) {
    return 'Intento #$n';
  }

  @override
  String get qcFailNotesHeader => 'Notas de falla';

  @override
  String qcPhotosCount(int n) {
    return 'Fotos ($n)';
  }

  @override
  String qcChecklistCount(int n) {
    return 'Lista ($n elementos)';
  }

  @override
  String qcItemNumber(int id) {
    return 'Elemento #$id';
  }

  @override
  String qcPhotoNumber(int n) {
    return 'Foto $n';
  }

  @override
  String get qcMgmtLoadFail => 'Error al cargar los elementos';

  @override
  String get qcMgmtAddTitle => 'Agregar elemento de lista';

  @override
  String get qcMgmtDeptLabel => 'Departamento QC';

  @override
  String get qcMgmtLabelField => 'Etiqueta';

  @override
  String get qcMgmtSortOrder => 'Orden';

  @override
  String get qcMgmtSeriesLabel => 'Aplica a serie';

  @override
  String get qcMgmtAllSeries => 'Todas las series';

  @override
  String qcMgmtCreateFail(String msg) {
    return 'Error al crear: $msg';
  }

  @override
  String get qcMgmtEditTitle => 'Editar elemento de lista';

  @override
  String get qcMgmtDeactivate => 'Desactivar';

  @override
  String get qcMgmtScreenTitle => 'Elementos de lista QC';

  @override
  String get qcMgmtEmpty => 'Sin elementos de lista';

  @override
  String qcMgmtSeriesValue(String series) {
    return 'Serie: $series';
  }

  @override
  String qcMgmtSeriesValueInactive(String series) {
    return 'Serie: $series (inactivo)';
  }

  @override
  String qcMgmtDeptFallback(int id) {
    return 'Depto $id';
  }

  @override
  String get payrollWeeklyReport => 'Reporte semanal';

  @override
  String get payrollPointMatrix => 'Matriz de puntos';

  @override
  String get payrollDollarRates => 'Tarifas en dólares';

  @override
  String get payrollCurrentWeekSummary => 'Resumen de la semana actual';

  @override
  String get payrollTotalPoints => 'Puntos totales';

  @override
  String get payrollProjected => 'Proyectado';

  @override
  String get payrollSteps => 'Pasos';

  @override
  String payrollReworks(int n) {
    return 'Retrabajos: $n';
  }

  @override
  String get payrollDailyBreakdown => 'Desglose diario (dom-sáb)';

  @override
  String get payrollDaySun => 'Dom';

  @override
  String get payrollDayMon => 'Lun';

  @override
  String get payrollDayTue => 'Mar';

  @override
  String get payrollDayWed => 'Mié';

  @override
  String get payrollDayThu => 'Jue';

  @override
  String get payrollDayFri => 'Vie';

  @override
  String get payrollDaySat => 'Sáb';

  @override
  String get payrollEstimated =>
      'Estimado a partir de datos disponibles del API';

  @override
  String get payrollDeptBreakdown => 'Desglose por departamento';

  @override
  String get payrollDeptEmpty => 'Sin actividad por departamento esta semana';

  @override
  String payrollPtsSuffix(String n) {
    return '$n pts';
  }

  @override
  String get payrollHistory => 'Historial';

  @override
  String get payrollHistoryNoAccess =>
      'El endpoint de historial es solo para gerentes en los permisos actuales';

  @override
  String get payrollHistoryEmpty => 'No se encontraron registros históricos';

  @override
  String get payrollDepartmentFallback => 'Departamento';

  @override
  String get payrollWeeklyReportTitle => 'Reporte semanal de nómina';

  @override
  String get payrollLockTitle => 'Bloquear semana de nómina';

  @override
  String payrollLockBody(String date) {
    return '¿Bloquear nómina para $date? Esto no se puede deshacer.';
  }

  @override
  String get payrollLockConfirm => 'Bloquear';

  @override
  String get payrollWeekLocked => 'Semana de nómina bloqueada';

  @override
  String get payrollAlreadyLocked => 'Ya bloqueada';

  @override
  String get payrollDateMustBeSunday => 'La fecha debe ser un domingo';

  @override
  String payrollLockFailed(String msg) {
    return 'Error al bloquear la semana: $msg';
  }

  @override
  String payrollCsvPrepared(int n) {
    return 'CSV preparado ($n caracteres)';
  }

  @override
  String get payrollWeekIsLocked => 'La semana está bloqueada';

  @override
  String get payrollExportCsv => 'Exportar CSV';

  @override
  String get payrollLockWeek => 'Bloquear semana';

  @override
  String get payrollColName => 'Nombre';

  @override
  String get payrollColPoints => 'Puntos';

  @override
  String get payrollColReworks => 'Retrabajos';

  @override
  String get payrollColGross => 'Bruto';

  @override
  String payrollTotals(String points, String gross) {
    return 'Totales: $points puntos • \$ $gross';
  }

  @override
  String get payrollPmTitle => 'Matriz de valores de puntos';

  @override
  String get payrollPmAddTooltip => 'Agregar valor de puntos';

  @override
  String get payrollPmNoData =>
      'Aún no se han configurado departamentos de producción ni modelos.';

  @override
  String get payrollPmTapCell =>
      'Toque cualquier celda para establecer o editar sus puntos.';

  @override
  String get payrollPmDept => 'Departamento';

  @override
  String payrollPmLoadFail(String msg) {
    return 'No se pudo cargar la matriz.\n$msg';
  }

  @override
  String get payrollPmNotLoaded => 'Departamentos y modelos aún no cargados.';

  @override
  String get payrollPmAddTitle => 'Agregar valor de puntos';

  @override
  String get payrollPmTrailerModel => 'Modelo de remolque';

  @override
  String get payrollPmSelectDept => 'Seleccione un departamento';

  @override
  String get payrollPmSelectModel => 'Seleccione un modelo';

  @override
  String get payrollPmPointsLabel => 'Puntos';

  @override
  String payrollPmEffective(String date) {
    return 'Vigente: $date';
  }

  @override
  String payrollPmAddFail(String msg) {
    return 'Error al agregar valor: $msg';
  }

  @override
  String get payrollPmSetTitle => 'Establecer valor de puntos';

  @override
  String get payrollPmEditTitle => 'Editar valor de puntos';

  @override
  String payrollPmSaveFail(String msg) {
    return 'Error al guardar: $msg';
  }

  @override
  String get payrollDrTitle => 'Tarifas en dólares';

  @override
  String get payrollDrEmpty => 'Aún no hay tarifas. Toque + para agregar una.';

  @override
  String payrollDrDeptFallback(int id) {
    return 'Departamento $id';
  }

  @override
  String payrollDrCurrent(String rate) {
    return 'Actual: \$ $rate / punto';
  }

  @override
  String payrollDrRatePerPoint(String rate) {
    return '\$ $rate / punto';
  }

  @override
  String payrollDrFromTo(String start, String end) {
    return 'De $start a $end';
  }

  @override
  String get payrollDrPresent => 'presente';

  @override
  String get payrollDrDeptsNotLoaded =>
      'Departamentos aún no cargados. Reintente.';

  @override
  String get payrollDrAddTitle => 'Agregar tarifa';

  @override
  String get payrollDrDollarLabel => 'Dólares por punto';

  @override
  String get payrollDrValidNumber => 'Ingrese un número positivo válido';

  @override
  String payrollDrAddFail(String msg) {
    return 'Error al agregar tarifa: $msg';
  }

  @override
  String get customersTitle => 'Clientes';

  @override
  String customersLoadFail(String msg) {
    return 'No se pudieron cargar los clientes: $msg';
  }

  @override
  String get customersSearchHint => 'Buscar nombre o empresa';

  @override
  String get customersFilterType => 'Tipo';

  @override
  String get customersFilterAll => 'Todos';

  @override
  String get customerTypeEndUser => 'Usuario final';

  @override
  String get customerTypeDealer => 'Distribuidor';

  @override
  String get customerTypeStockLoc => 'Almacén';

  @override
  String get customerTypeStockLocation => 'Ubicación de stock';

  @override
  String get customerTypeStockShort => 'Stock';

  @override
  String customersActiveTrailers(int n) {
    return 'Remolques activos: $n';
  }

  @override
  String get customersPrev => 'Anterior';

  @override
  String get customersNext => 'Siguiente';

  @override
  String customersPageOf(int n, int total) {
    return 'Página $n / $total';
  }

  @override
  String get customersNew => 'Nuevo cliente';

  @override
  String get customerFormCreateTitle => 'Crear cliente';

  @override
  String get customerFormEditTitle => 'Editar cliente';

  @override
  String get customerFormName => 'Nombre *';

  @override
  String get customerFormCompany => 'Empresa';

  @override
  String get customerFormType => 'Tipo de cliente';

  @override
  String get customerFormPhone => 'Teléfono';

  @override
  String get customerFormEmail => 'Correo electrónico';

  @override
  String get customerFormBilling => 'Dirección de facturación';

  @override
  String get customerFormDelivery => 'Dirección de entrega';

  @override
  String get customerFormSmsOptOut => 'Excluir de SMS';

  @override
  String get customerFormNotes => 'Notas';

  @override
  String get customerFormSaveChanges => 'Guardar cambios';

  @override
  String customerFormSaveFail(String msg) {
    return 'Error al guardar el cliente: $msg';
  }

  @override
  String get customerDetailTitle => 'Detalle del cliente';

  @override
  String customerDetailLoadFail(String msg) {
    return 'No se pudo cargar el detalle: $msg';
  }

  @override
  String get customerDetailDeleteTooltip => 'Eliminar cliente';

  @override
  String get customerDetailTabTrailers => 'Historial de remolques';

  @override
  String get customerDetailTabDeliveries => 'Historial de entregas';

  @override
  String get customerDetailNotFound => 'Cliente no encontrado';

  @override
  String get customerDetailDeleteTitle => '¿Eliminar cliente?';

  @override
  String customerDetailDeleteBody(String name) {
    return 'Esto elimina permanentemente a \"$name\".';
  }

  @override
  String get customerDetailHasTrailersTitle => 'El cliente tiene remolques';

  @override
  String customerDetailHasTrailersBody(String name, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n remolques',
      one: '1 remolque',
    );
    return '\"$name\" está referenciado por $_temp0.\n\nEliminar el cliente también eliminará todos los remolques asociados con su historial de producción, inspecciones QC, fotos, entregas y mensajes.\n\nEsto no se puede deshacer.';
  }

  @override
  String customerDetailDeleteCascade(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n remolques',
      one: '1 remolque',
    );
    return 'Eliminar cliente + $_temp0';
  }

  @override
  String customerDetailDeletedCascade(String name, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n remolques',
      one: '1 remolque',
    );
    return 'Eliminado \"$name\" y $_temp0';
  }

  @override
  String customerDetailDeleted(String name) {
    return 'Cliente \"$name\" eliminado';
  }

  @override
  String customerDetailDeleteFailed(String msg) {
    return 'Error al eliminar: $msg';
  }

  @override
  String customerDetailSmsUpdateFailed(String msg) {
    return 'Error al actualizar preferencia SMS: $msg';
  }

  @override
  String customerDetailPhone(String value) {
    return 'Teléfono: $value';
  }

  @override
  String customerDetailEmail(String value) {
    return 'Correo: $value';
  }

  @override
  String customerDetailQbId(String value) {
    return 'ID QuickBooks: $value';
  }

  @override
  String get customerDetailUpdating => 'Actualizando...';

  @override
  String customerDetailBilling(String value) {
    return 'Dirección de facturación: $value';
  }

  @override
  String customerDetailDelivery(String value) {
    return 'Dirección de entrega: $value';
  }

  @override
  String customerDetailNotes(String value) {
    return 'Notas: $value';
  }

  @override
  String get customerDetailNoTrailerHistory => 'Sin historial de remolques';

  @override
  String get customerDetailNoDeliveryHistory => 'Sin historial de entregas';

  @override
  String customerDetailVin(String value) {
    return 'VIN: $value';
  }

  @override
  String customerDetailStatusValue(String value) {
    return 'Estado: $value';
  }

  @override
  String get customerDetailOpen => 'Abrir';

  @override
  String customerDetailDeliveryHash(int id) {
    return 'Entrega #$id';
  }

  @override
  String customerDetailTrailerValue(String value) {
    return 'Remolque: $value';
  }

  @override
  String customerDetailTypeStatus(String type, String status) {
    return 'Tipo: $type • Estado: $status';
  }

  @override
  String get notificationsTitle => 'Centro de notificaciones';

  @override
  String get notificationsMarkAllRead => 'Marcar todas leídas';

  @override
  String get notificationsEmpty => 'Sin notificaciones todavía';

  @override
  String get notificationsDelete => 'Eliminar';

  @override
  String messagesTitle(int id) {
    return 'Mensajes del remolque #$id';
  }

  @override
  String get messagesRecipientLabel => 'ID del usuario destinatario';

  @override
  String messagesUserFallback(int id) {
    return 'Usuario $id';
  }

  @override
  String get messagesHint => 'Mensaje...';

  @override
  String get messagesSend => 'Enviar';

  @override
  String messagesSendFail(String msg) {
    return 'Error al enviar mensaje: $msg';
  }

  @override
  String get notificationPanelTitle => 'Notificaciones';

  @override
  String get deliveryListTabScheduled => 'Programadas';

  @override
  String get deliveryListTabCompleted => 'Completadas';

  @override
  String get deliveryListTabFailed => 'Fallidas';

  @override
  String get deliveryListFabBatches => 'Lotes';

  @override
  String get deliveryListFabCreate => 'Crear entrega';

  @override
  String get deliveryListEmpty => 'No se encontraron entregas';

  @override
  String get deliveryListFilterType => 'Tipo de entrega';

  @override
  String get deliveryListFilterAllTypes => 'Todos los tipos';

  @override
  String get deliveryListFilterFactoryPickup => 'Recogida en fábrica';

  @override
  String get deliveryListFilterSinglePull => 'Tracción única';

  @override
  String get deliveryListFilterStackToDealer => 'Apilada al distribuidor';

  @override
  String get deliveryListFilterStackToLocation => 'Apilada a ubicación';

  @override
  String get deliveryListFilterDriverId => 'ID conductor';

  @override
  String get deliveryListFilterDateRange => 'Rango de fechas';

  @override
  String get deliveryListFilterClearDates => 'Limpiar fechas';

  @override
  String deliveryListBatchTitle(int n) {
    return 'Entrega por lote — $n remolques';
  }

  @override
  String deliveryListDestination(String value) {
    return 'Destino: $value';
  }

  @override
  String deliveryListDriverLabel(String value) {
    return 'Conductor: $value';
  }

  @override
  String deliveryDetailTitle(int id) {
    return 'Entrega #$id';
  }

  @override
  String get deliveryDetailNotFound => 'Entrega no encontrada';

  @override
  String get deliveryDetailDeleteTooltip => 'Eliminar entrega';

  @override
  String get deliveryDetailSectionTrailer => 'Remolque';

  @override
  String get deliveryDetailSectionDriver => 'Conductor';

  @override
  String get deliveryDetailSectionDestination => 'Destino';

  @override
  String get deliveryDetailSectionBalance => 'Saldo pendiente';

  @override
  String get deliveryDetailSectionPickedUp => 'Recogido por';

  @override
  String get deliveryDetailSectionFailReason => 'Motivo de falla';

  @override
  String deliveryDetailSo(String value) {
    return 'SO: $value';
  }

  @override
  String deliveryDetailModel(String value) {
    return 'Modelo: $value';
  }

  @override
  String deliveryDetailCustomer(String value) {
    return 'Cliente: $value';
  }

  @override
  String deliveryDetailAssigned(String value) {
    return 'Asignado: $value';
  }

  @override
  String get deliveryDetailOpenMaps => 'Abrir en Maps';

  @override
  String get deliveryDetailTextCustomer => 'Enviar SMS al cliente';

  @override
  String get deliveryDetailCompleteAction => 'Completar entrega';

  @override
  String get deliveryDetailMarkFailed => 'Marcar fallida';

  @override
  String get deliveryDetailNoAddress =>
      'Sin dirección de destino para esta entrega.';

  @override
  String get deliveryDetailNoPhone =>
      'Sin número telefónico para este cliente.';

  @override
  String deliveryDetailCompleteFail(String msg) {
    return 'Error al completar la entrega: $msg';
  }

  @override
  String get deliveryDetailCompleteBatchTitle => 'Completar lote';

  @override
  String deliveryDetailCompleteBatchBody(int n, String batch) {
    return '¿Marcar los $n remolques en $batch como entregados? Esto completa el lote en un paso.';
  }

  @override
  String get deliveryDetailMarkAllDelivered => 'Marcar todos entregados';

  @override
  String deliveryDetailBatchAllDelivered(String batch) {
    return '$batch — todos los remolques entregados.';
  }

  @override
  String deliveryDetailBatchFail(String msg) {
    return 'Error al completar el lote: $msg';
  }

  @override
  String get deliveryDetailDeleteTitle => 'Eliminar entrega';

  @override
  String deliveryDetailDeleteBody(String so) {
    return '¿Eliminar esta entrega para $so? El remolque vuelve a listo para entrega. No se puede deshacer.';
  }

  @override
  String deliveryDetailDeleted(String so) {
    return 'Entrega $so eliminada.';
  }

  @override
  String deliveryDetailDeleteFail(String msg) {
    return 'Error al eliminar entrega: $msg';
  }

  @override
  String get deliveryDetailMarkFailedTitle => 'Marcar entrega fallida';

  @override
  String deliveryDetailMarkFailedError(String msg) {
    return 'Error al marcar fallida: $msg';
  }

  @override
  String get deliveryDetailStatusLabel => 'Estado';

  @override
  String deliveryDetailTrailerCount(int n) {
    return '$n remolques';
  }

  @override
  String deliveryDetailBatchTitle(String batch) {
    return 'Lote — $batch';
  }

  @override
  String deliveryDetailBatchStatus(String value) {
    return 'Estado: $value';
  }

  @override
  String get deliveryDetailUnassigned => 'Sin asignar';

  @override
  String get deliveryDetailCompleteEntireBatch => 'Completar lote completo';

  @override
  String get driverDeliveriesTitle => 'Mis entregas';

  @override
  String driverDeliveriesLoadFail(String msg) {
    return 'Error al cargar entregas: $msg';
  }

  @override
  String driverCompleteBatchBody(int n, String batch, String dest) {
    return 'Confirme que los $n remolques en $batch fueron entregados a $dest.';
  }

  @override
  String get driverCompleteTrailerTitle => 'Completar remolque';

  @override
  String driverCompleteTrailerBody(String so) {
    return '¿Marcar $so como entregado? Los demás remolques del lote permanecen en tránsito.';
  }

  @override
  String get driverMarkDelivered => 'Marcar entregado';

  @override
  String driverTrailerDelivered(String so) {
    return '$so entregado.';
  }

  @override
  String driverMarkSoFailed(String so) {
    return 'Marcar $so fallido';
  }

  @override
  String driverSoMarkedFailed(String so) {
    return '$so marcado fallido.';
  }

  @override
  String get driverTheDestination => 'el destino';

  @override
  String get driverCompletedToday => 'Completados hoy';

  @override
  String get createDeliveryTitle => 'Crear entrega';

  @override
  String get createDeliverySubmit => 'Crear entrega';

  @override
  String get createDeliveryCreated => 'Entrega creada';

  @override
  String createDeliveryFail(String msg) {
    return 'Error al crear entrega: $msg';
  }

  @override
  String get batchScreenTitle => 'Lotes de entrega';

  @override
  String get batchScreenEmpty => 'Sin lotes todavía. Toque + para crear uno.';

  @override
  String get batchScreenNewBatch => 'Nuevo lote';

  @override
  String batchCreateFail(String msg) {
    return 'Error al crear lote: $msg';
  }

  @override
  String get stockInventoryTitle => 'Inventario de stock';

  @override
  String get stockInventoryEmpty => 'No se encontraron remolques de stock.';

  @override
  String stockInventoryLoadFail(String msg) {
    return 'Error al cargar inventario: $msg';
  }

  @override
  String get completeDeliveryDialogTitle => 'Completar entrega';

  @override
  String get completeDeliveryPaymentLabel => 'Pago cobrado';

  @override
  String get completeDeliveryConfirm => 'Completar';

  @override
  String get failReasonDialogLabel => 'Motivo';

  @override
  String get failReasonDialogHint => '¿Por qué falló la entrega?';

  @override
  String get failReasonRequired => 'El motivo es obligatorio';

  @override
  String get adminDashboardTitle => 'Panel de administración';

  @override
  String get adminStatTotalUsers => 'Usuarios totales';

  @override
  String get adminStatActiveTrailers => 'Remolques activos';

  @override
  String get adminStatWeeklyOutput => 'Producción semanal';

  @override
  String get adminStatQcFailRate => 'Tasa de fallas QC';

  @override
  String get adminNavUsersSubtitle =>
      'Crear/editar/desactivar usuarios y filtrar por rol';

  @override
  String get adminNavDeptsSubtitle =>
      'Editar umbrales y revisar mapeo de flujo';

  @override
  String get adminNavWorkflowSubtitle => 'Ver pasos de 4 series de remolques';

  @override
  String get adminNavAuditSubtitle =>
      'Eventos paginados con cambios antes/después';

  @override
  String get adminNavReportsSubtitle =>
      'Resumen semanal y producción por trabajador';

  @override
  String get adminNavReports => 'Informes de producción';

  @override
  String get adminNavWorkflowTemplates => 'Plantillas de flujo';

  @override
  String get adminUsers => 'Gestión de usuarios';

  @override
  String get adminAuditLog => 'Registro de auditoría';

  @override
  String get adminReports => 'Informes';

  @override
  String get adminDepartmentConfig => 'Config. de departamentos';

  @override
  String get adminWorkflow => 'Visor de flujo';

  @override
  String get adminChecklists => 'Listas QC';

  @override
  String get auditLogTitle => 'Registro de auditoría';

  @override
  String get auditLogEmpty => 'Sin entradas de auditoría';

  @override
  String auditLogLoadFail(String msg) {
    return 'Error al cargar auditoría: $msg';
  }

  @override
  String get reportsTitle => 'Informes';

  @override
  String reportsLoadFail(String msg) {
    return 'Error al cargar informes: $msg';
  }

  @override
  String get userMgmtTitle => 'Gestión de usuarios';

  @override
  String get userMgmtAdd => 'Agregar usuario';

  @override
  String get userMgmtEdit => 'Editar usuario';

  @override
  String get userMgmtDeactivate => 'Desactivar';

  @override
  String get userMgmtReactivate => 'Reactivar';

  @override
  String get userMgmtEmpty => 'Sin usuarios todavía';

  @override
  String userMgmtLoadFail(String msg) {
    return 'Error al cargar usuarios: $msg';
  }

  @override
  String userMgmtSaveFail(String msg) {
    return 'Error al guardar usuario: $msg';
  }

  @override
  String get deptConfigTitle => 'Config. de departamentos';

  @override
  String get deptConfigEmpty => 'Sin departamentos configurados';

  @override
  String deptConfigLoadFail(String msg) {
    return 'Error al cargar departamentos: $msg';
  }

  @override
  String get workflowViewerTitle => 'Visor de flujo';

  @override
  String get photoCaptureTakePhoto => 'Tomar foto';

  @override
  String get photoCaptureFromGallery => 'Desde galería';

  @override
  String get photoCaptureRemove => 'Quitar';

  @override
  String get photoCaptureUploading => 'Cargando...';

  @override
  String get photoCaptureFailed => 'Carga fallida';

  @override
  String get imageViewerTitle => 'Foto';

  @override
  String get pdfViewerTitle => 'PDF';

  @override
  String get pdfViewerLoadFail => 'Error al cargar el PDF';

  @override
  String get stockLocationChipsLabel => 'Destino de stock';

  @override
  String get stockLocationChipsLoading => 'Cargando ubicaciones...';

  @override
  String get stockLocationChipsLoadFail => 'Error al cargar ubicaciones';

  @override
  String get adminAuditEntityType => 'Tipo de entidad';

  @override
  String get adminAuditEntityTrailer => 'Remolque';

  @override
  String get adminAuditEntityStep => 'Paso de producción';

  @override
  String get adminAuditEntityQcInspection => 'Inspección QC';

  @override
  String get adminAuditEntityDelivery => 'Entrega';

  @override
  String get adminAuditEntityPayroll => 'Nómina';

  @override
  String get adminAuditEntityUser => 'Usuario';

  @override
  String get adminAuditUserIdLabel => 'ID de usuario';

  @override
  String get adminAuditEmptyMessage =>
      'Ninguna entrada coincide con estos filtros.';

  @override
  String get adminPullToRefresh => 'Desliza hacia abajo para actualizar.';

  @override
  String get adminAuditOldValues => 'Valores anteriores';

  @override
  String get adminAuditNewValues => 'Valores nuevos';

  @override
  String get adminReportsNoReport => 'Sin informe';

  @override
  String get adminReportWeeklySteps => 'Pasos completados (semana)';

  @override
  String get adminReportWeeklyPoints => 'Puntos (semana)';

  @override
  String get adminReportQcFailTrend => 'Tendencia de fallas QC';

  @override
  String get adminReportAvgTimePerStep => 'Tiempo promedio por paso';

  @override
  String get adminReportStalledTrailers => 'Remolques detenidos';

  @override
  String get adminReportNotAvailable => 'N/D (endpoint no disponible)';

  @override
  String get adminReportUseProdDashboard =>
      'Usa la vista de cola del panel de producción';

  @override
  String get adminReportWorkerSummary => 'Resumen por trabajador';

  @override
  String adminReportRoleValue(String role) {
    return 'Rol: $role';
  }

  @override
  String adminReportStepsPtsLine(String steps, String pts) {
    return '$steps pasos\n$pts pts';
  }

  @override
  String get userMgmtSearchHint => 'Buscar nombre o correo';

  @override
  String get userMgmtFilterRole => 'Rol';

  @override
  String get userMgmtFilterStatus => 'Estado';

  @override
  String get userMgmtInactive => 'Inactivo';

  @override
  String get userMgmtEmptyFiltered =>
      'No se encontraron usuarios para los filtros actuales.';

  @override
  String userMgmtIdChip(int id) {
    return 'ID: $id';
  }

  @override
  String userMgmtDeptChip(String value) {
    return 'Depto: $value';
  }

  @override
  String userMgmtLocationChip(String value) {
    return 'Ubicación: $value';
  }

  @override
  String userMgmtCreatedChip(String value) {
    return 'Creado: $value';
  }

  @override
  String get userMgmtNotAvailable => 'N/D';

  @override
  String get userMgmtDeactivateTitle => '¿Desactivar usuario?';

  @override
  String userMgmtDeactivateBody(String name) {
    return '$name perderá acceso inmediatamente pero su historial se conserva. Puedes reactivar luego.';
  }

  @override
  String userMgmtDeactivated(String name) {
    return '$name desactivado';
  }

  @override
  String userMgmtReactivated(String name) {
    return '$name reactivado';
  }

  @override
  String get userMgmtDeleteTitle => '¿Eliminar usuario permanentemente?';

  @override
  String userMgmtDeleteBody(String name) {
    return 'Esto elimina permanentemente a $name de la base de datos. No se puede deshacer.';
  }

  @override
  String get userMgmtDeleteHelper =>
      'El usuario debe estar desactivado primero. Los usuarios con actividad histórica (pasos completados, inspecciones, entregas, mensajes) no pueden eliminarse — mantenlos desactivados para preservar la auditoría.';

  @override
  String get userMgmtDeleteForever => 'Eliminar permanentemente';

  @override
  String userMgmtDeleted(String name) {
    return '$name eliminado';
  }

  @override
  String userMgmtDeleteFail(String msg) {
    return 'Error al eliminar: $msg';
  }

  @override
  String get userMgmtCreateAction => 'Crear';

  @override
  String get userMgmtNameLabel => 'Nombre';

  @override
  String get userMgmtPasswordOptional => 'Contraseña (opcional)';

  @override
  String get userMgmtPhoneOptional => 'Teléfono (opcional)';

  @override
  String get userMgmtDeptIdLabel => 'ID de departamento principal';

  @override
  String get userMgmtLocationIdLabel => 'ID de ubicación principal';

  @override
  String get roleOwner => 'Propietario';

  @override
  String get roleProductionManager => 'Gerente de producción';

  @override
  String get roleProductionManagerShort => 'Gte Prod';

  @override
  String get roleTransportManager => 'Gerente de transporte';

  @override
  String get roleTransportManagerShort => 'Gte Transp';

  @override
  String get roleQcInspector => 'Inspector QC';

  @override
  String get roleQcShort => 'QC';

  @override
  String get roleWorker => 'Trabajador';

  @override
  String get roleDriver => 'Conductor';

  @override
  String get roleSales => 'Ventas';

  @override
  String get roleOffice => 'Oficina';

  @override
  String get rolePurchasing => 'Compras';

  @override
  String get deptTypeQc => 'QC';

  @override
  String get deptTypeProduction => 'Producción';

  @override
  String deptConfigSubtitle(String type, String completion, int hours) {
    return '$type • $completion • Detención ${hours}h';
  }

  @override
  String get deptConfigEditThreshold => 'Editar umbral';

  @override
  String get deptConfigWorkflowDiagram => 'Diagrama de flujo por serie';

  @override
  String deptConfigUpdateFail(String msg) {
    return 'Error al actualizar el umbral: $msg';
  }

  @override
  String deptConfigEditThresholdTitle(String code) {
    return 'Editar umbral de $code';
  }

  @override
  String get deptConfigHoursLabel => 'Horas';

  @override
  String createDeliveryLoadFail(String msg) {
    return 'Error al cargar datos del formulario: $msg';
  }

  @override
  String get createDeliverySingleMode => 'Individual';

  @override
  String get createDeliveryBatchMode => 'Lote';

  @override
  String get createDeliveryCreateBatch => 'Crear lote';

  @override
  String get createDeliveryRecordPickup => 'Registrar recogida';

  @override
  String get createDeliveryReadyTrailer => 'Remolque listo';

  @override
  String get createDeliveryTrailerRequired => 'Se requiere un remolque';

  @override
  String get createDeliveryFactoryPickupHelper =>
      'Se registra como recogido de inmediato — el cliente retira el remolque en la fábrica.';

  @override
  String get createDeliveryPickedUpBy => 'Recogido por (opcional)';

  @override
  String get createDeliveryAmountCollected => 'Monto cobrado (opcional)';

  @override
  String get createDeliveryAssignDriver => 'Asignar conductor';

  @override
  String get createDeliveryDestinationLocation => 'Ubicación de destino';

  @override
  String get createDeliveryYardHelper =>
      'Elija un yard o déjelo sin seleccionar e ingrese una dirección personalizada abajo.';

  @override
  String get createDeliveryClearYardAddress =>
      'Quitar yard, usar dirección personalizada';

  @override
  String get createDeliveryCustomAddress =>
      'Dirección de destino personalizada';

  @override
  String get createDeliveryContactPhone => 'Teléfono de contacto (opcional)';

  @override
  String get createDeliveryDriverTextsHelper =>
      'El conductor envía SMS a este número';

  @override
  String get createDeliveryBalanceDue => 'Saldo pendiente';

  @override
  String get createDeliveryAddToBatch => 'Agregar a lote existente (opcional)';

  @override
  String get createDeliveryNoBatch => 'Sin lote';

  @override
  String createDeliveryBatchEntry(String batch, String status) {
    return '$batch ($status)';
  }

  @override
  String get createDeliveryBatchNumber => 'Número de lote';

  @override
  String get createDeliveryBatchNumberRequired =>
      'El número de lote es obligatorio';

  @override
  String get createDeliveryBatchType => 'Tipo de lote';

  @override
  String get createDeliveryBatchTypeDealer => 'Distribuidor';

  @override
  String get createDeliveryBatchTypeBfLocation => 'Ubicación Bigfoot';

  @override
  String get createDeliveryBatchYardHelper =>
      'Elija un yard o déjelo sin seleccionar e ingrese un nombre de destino abajo.';

  @override
  String get createDeliveryClearYardName =>
      'Quitar yard, usar nombre personalizado';

  @override
  String get createDeliveryDestinationName =>
      'Nombre del destino (para distribuidores)';

  @override
  String createDeliveryTrailersSelected(int n) {
    return 'Remolques  ($n seleccionados)';
  }

  @override
  String get createDeliverySelectTrailer =>
      'Seleccione al menos un remolque para el lote.';

  @override
  String get createDeliveryNotReady =>
      'Un remolque seleccionado no está listo para entrega';

  @override
  String get createDeliveryNoReadyTrailers =>
      'No hay remolques listos para entrega disponibles.';

  @override
  String createDeliveryStockedAt(String value) {
    return 'Almacenado en $value';
  }

  @override
  String createDeliveryCreateFail(String msg) {
    return 'Error al crear: $msg';
  }

  @override
  String get batchScreenDeleteTitle => 'Eliminar lote';

  @override
  String batchScreenDeleteBody(String batch, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n registros de entrega',
      one: '1 registro de entrega',
    );
    return '¿Eliminar $batch? Esto elimina el lote y sus $_temp0. Los remolques no entregados vuelven al pool de listos para entrega.';
  }

  @override
  String batchScreenDeleted(String batch) {
    return '$batch eliminado.';
  }

  @override
  String batchScreenDeleteFail(String msg) {
    return 'Error al eliminar: $msg';
  }

  @override
  String batchScreenCompleteFail(String msg) {
    return 'Error al completar: $msg';
  }

  @override
  String batchScreenTypeLabel(String value) {
    return 'Tipo: $value';
  }

  @override
  String batchScreenDriverLabel(String value) {
    return 'Conductor: $value';
  }

  @override
  String batchScreenDestinationLabel(String value) {
    return 'Destino: $value';
  }

  @override
  String batchScreenTrailersLabel(int n) {
    return 'Remolques: $n';
  }

  @override
  String batchScreenUpdateTitle(String batch) {
    return 'Actualizar $batch';
  }

  @override
  String get batchScreenDriverField => 'Conductor';

  @override
  String get batchScreenCustomDestination => 'Nombre de destino personalizado';

  @override
  String get batchScreenDestinationName => 'Nombre del destino';

  @override
  String get batchScreenAddTrailerId => 'Agregar ID de remolque (opcional)';

  @override
  String get batchScreenRemoveDeliveryId => 'Quitar ID de entrega (opcional)';

  @override
  String get batchScreenCompletedNote =>
      'Lote completado — todos los remolques entregados.';

  @override
  String get batchScreenUpdate => 'Actualizar';

  @override
  String get stockInventoryEmptyBody =>
      'No hay remolques en stock en ningún yard.\nDesliza hacia abajo para actualizar.';

  @override
  String get stockInventoryUnknownDate => 'Fecha desconocida';

  @override
  String get stockInventoryDelivered => 'Entregado';

  @override
  String get stockInventoryDeliveredBy => 'Entregado por';

  @override
  String driverDeliveredOn(String date) {
    return 'Entregado $date';
  }
}
