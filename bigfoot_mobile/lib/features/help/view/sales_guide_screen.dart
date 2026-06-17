import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Plain-language, step-by-step guide for the sales team. Reached from the
/// "How to Use" item in the sales account's menu/drawer. Intentionally simple:
/// numbered steps, big headings, no jargon — so anyone can follow it.
///
/// Content is provided in both English and Spanish and switches with the app's
/// current language (the in-app language toggle). Kept inline here rather than
/// in the .arb files because it's long-form prose, not short UI labels.
class SalesGuideScreen extends StatelessWidget {
  const SalesGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final sections = es ? _esSections : _enSections;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _GuideHeader(
            title: es ? 'Cómo usar la aplicación' : 'How to Use the App',
            subtitle: es
                ? 'Una guía rápida para el equipo de ventas. Siga los pasos '
                    'numerados en cada sección.'
                : 'A quick guide for the sales team. Follow the numbered steps '
                    'in each section.',
          ),
          const SizedBox(height: 20),
          for (final s in sections)
            _GuideSection(
              number: s.number,
              icon: s.icon,
              title: s.title,
              subtitle: s.subtitle,
              steps: s.steps,
            ),
          const SizedBox(height: 8),
          _GuideFooter(
            text: es
                ? 'Consejo: puede volver a esta guía en cualquier momento desde '
                    'el menú — "Cómo usar".'
                : 'Tip: you can come back to this guide any time from the menu — '
                    '"How to Use".',
          ),
        ],
      ),
    );
  }
}

// ── Content ──────────────────────────────────────────────────────────────────

class _SectionData {
  final int number;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> steps;

  const _SectionData({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.steps,
  });
}

const List<_SectionData> _enSections = [
  _SectionData(
    number: 1,
    icon: Icons.inventory_2_outlined,
    title: 'Check Stock Inventory',
    subtitle: 'See which finished trailers are sitting at each yard.',
    steps: [
      'On the Dashboard, tap "Stock Inventory".',
      'Tap a location to open that yard.',
      'Use the filters at the top to find the trailer you want.',
    ],
  ),
  _SectionData(
    number: 2,
    icon: Icons.local_shipping_outlined,
    title: 'View Trailers in Production',
    subtitle: 'See every trailer and exactly where it is in the build.',
    steps: [
      'Tap "Trailers" in the menu to see all trailers.',
      'Use the search bar at the top to find a trailer by SO# or customer.',
      'Tap a trailer to open it — you will see what production stage it is in.',
      'Open the Workflow / Steps to see every stage the trailer moves through.',
      'Open History to see how it has moved through production over time.',
      'Scroll to Photos to see pictures of the trailer taken throughout the build.',
    ],
  ),
  _SectionData(
    number: 3,
    icon: Icons.add_box_outlined,
    title: 'Create a New Sales Order',
    subtitle: 'Every new sales order needs a trailer created in the app.',
    steps: [
      'Tap "Trailers".',
      'Tap the + button in the bottom-right corner.',
      'Enter the SO number.',
      'Choose the trailer model.',
      'Enter the length and color.',
      'If there are any notes, record them in the notes section.',
      'If it is being built as open stock: turn on "Stock Build".',
      'If it is being built for a customer: fill out the customer name, then '
          'select the location the trailer will be coming from.',
      'For a Virginia customer: fill out the customer name and select Virginia '
          'as well.',
      'Save.',
    ],
  ),
  _SectionData(
    number: 4,
    icon: Icons.delivery_dining_outlined,
    title: 'Make a Delivery',
    subtitle: 'When a trailer needs to go out — a single pull or a stack.',
    steps: [
      'Tap "Deliveries".',
      'Tap "Create Delivery".',
      'Choose the type: a Single Pull (one trailer), or a Batch (a stack going '
          'together).',
      'For a batch, attach all the associated trailers.',
      'Assign it to the correct driver.',
      'Right now we only have one driver entered: Kyle (dev driver).',
      'Save.',
    ],
  ),
];

const List<_SectionData> _esSections = [
  _SectionData(
    number: 1,
    icon: Icons.inventory_2_outlined,
    title: 'Consultar el inventario de stock',
    subtitle: 'Vea qué remolques terminados hay en cada yard.',
    steps: [
      'En el Panel, toque "Inventario de stock".',
      'Toque una ubicación para abrir ese yard.',
      'Use los filtros de la parte superior para encontrar el remolque que busca.',
    ],
  ),
  _SectionData(
    number: 2,
    icon: Icons.local_shipping_outlined,
    title: 'Ver remolques en producción',
    subtitle: 'Vea cada remolque y exactamente en qué punto de la fabricación está.',
    steps: [
      'Toque "Remolques" en el menú para ver todos los remolques.',
      'Use la barra de búsqueda de arriba para encontrar un remolque por SO# o cliente.',
      'Toque un remolque para abrirlo: verá en qué etapa de producción está.',
      'Abra el Flujo de trabajo / Pasos para ver cada etapa por la que pasa el remolque.',
      'Abra el Historial para ver cómo ha avanzado por la producción con el tiempo.',
      'Desplácese a Fotos para ver imágenes del remolque tomadas durante la fabricación.',
    ],
  ),
  _SectionData(
    number: 3,
    icon: Icons.add_box_outlined,
    title: 'Crear una nueva orden de venta',
    subtitle: 'Cada nueva orden de venta necesita crear un remolque en la aplicación.',
    steps: [
      'Toque "Remolques".',
      'Toque el botón + en la esquina inferior derecha.',
      'Ingrese el número de SO.',
      'Elija el modelo de remolque.',
      'Ingrese el largo y el color.',
      'Si hay notas, regístrelas en la sección de notas.',
      'Si se fabrica como stock abierto: active "Stock Build".',
      'Si se fabrica para un cliente: complete el nombre del cliente y luego '
          'seleccione la ubicación de donde vendrá el remolque.',
      'Para un cliente de Virginia: complete el nombre del cliente y seleccione '
          'Virginia también.',
      'Guarde.',
    ],
  ),
  _SectionData(
    number: 4,
    icon: Icons.delivery_dining_outlined,
    title: 'Realizar una entrega',
    subtitle: 'Cuando un remolque debe salir: un solo viaje o un grupo (stack).',
    steps: [
      'Toque "Entregas".',
      'Toque "Crear entrega".',
      'Elija el tipo: Single Pull (un remolque) o Batch/Lote (un grupo que va junto).',
      'Para un lote, adjunte todos los remolques asociados.',
      'Asígnela al conductor correcto.',
      'Por ahora solo tenemos un conductor ingresado: Kyle (dev driver).',
      'Guarde.',
    ],
  ),
];

// ── Widgets ──────────────────────────────────────────────────────────────────

class _GuideHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _GuideHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_book_outlined,
                  color: AppColors.navy, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.navy.withValues(alpha: 0.7),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _GuideSection extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> steps;

  const _GuideSection({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section heading
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.amber, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$number. $title',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.white.withValues(alpha: 0.8),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Numbered steps
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  _Step(index: i + 1, text: steps[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final String text;

  const _Step({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideFooter extends StatelessWidget {
  final String text;

  const _GuideFooter({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.navy, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.navy.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
