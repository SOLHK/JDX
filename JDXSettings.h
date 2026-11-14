#import <Foundation/Foundation.h>

#ifndef JDX_SETTINGS_H
#define JDX_SETTINGS_H

void JDXInstallSettingsEntry(void);
// These two functions collect runtime state on the main thread.
NSDictionary *JDXRuntimeSnapshot(void);
void JDXRunDiagnostics(void);

#endif
