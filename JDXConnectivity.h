#import <Foundation/Foundation.h>

#ifndef JDX_CONNECTIVITY_H
#define JDX_CONNECTIVITY_H

// Passive system-path metadata only. No requests, endpoints, proxy credentials,
// certificate changes, or replacements of the host networking implementation.
void JDXConnectivityStart(void);
NSDictionary *JDXConnectivitySnapshot(void);

#endif
