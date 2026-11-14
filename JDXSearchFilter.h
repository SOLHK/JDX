#import <Foundation/Foundation.h>

#ifndef JDX_SEARCH_FILTER_H
#define JDX_SEARCH_FILTER_H

/* Original input identity is preserved on unknown or inconsistent schemas.
 * The helper never mutates host dictionaries, arrays, rows or product models. */
id JDXFilterSearchResult(id result, NSUInteger *removed, NSString **reasonCode);

#endif
