// Backwards-compatible facade for the shared Lipila FX service.
// The real implementation lives in the Lipila payment integration at
// `features/give/data/lipila_fx_service.dart` so other projects that wire
// Lipila can reuse it. This file just re-exports the providers/service.
export 'package:church_on_app/features/give/data/lipila_fx_service.dart';
