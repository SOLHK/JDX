#ifndef JDX_DIAGNOSTICS_H
#define JDX_DIAGNOSTICS_H

#import <Foundation/Foundation.h>

// Only pass fixed metadata and reason codes. Never pass a request, response,
// exception reason, account data, user-visible text, or a complete file path.
void JDXDiagnosticsStart(NSDictionary *environment);
void JDXDiagnosticsSetEnhanced(BOOL enabled);
BOOL JDXDiagnosticsEnhanced(void);
void JDXLog(NSString *event, NSDictionary *fields);
void JDXRecordRule(NSString *ruleID, NSString *outcome, NSUInteger amount);
void JDXRecordHook(NSDictionary *record);
void JDXRecordPage(NSString *className);
NSDictionary *JDXDiagnosticsSnapshot(void);
NSString *JDXDiagnosticsSummary(void);
// Call on a background queue. The caller explicitly chooses whether to share.
NSURL *JDXExportDiagnostics(NSDictionary *state, NSError **error);
void JDXClearDiagnostics(void);

#endif
