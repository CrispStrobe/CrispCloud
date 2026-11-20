/// Portable, explicitly invoked Office macros and MCP tool integration.
///
/// Native plans, recorded tool calls, and registered language compilers all
/// execute through the same document operations. Embedded VBA remains inert.
library;

export 'src/automation/office_macro_language.dart';
export 'src/automation/office_macro_mcp.dart';
export 'src/automation/office_macro_model.dart'
    show
        OfficeMacro,
        OfficeMacroException,
        OfficeMacroParameter,
        OfficeMacroParameterType,
        OfficeMacroStep;
export 'src/automation/office_macro_runtime.dart';
export 'src/automation/office_operations.dart'
    show OfficeMacroAssetResolver, OfficeMacroFormat, OfficeOperationCatalog;
export 'src/automation/office_vba_language.dart'
    show
        OfficeVbaCompileException,
        OfficeVbaMacroLanguage,
        OfficeVbaWordMacroLanguage,
        OfficeVbaPowerPointMacroLanguage;
