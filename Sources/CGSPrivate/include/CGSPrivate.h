#ifndef CGS_PRIVATE_H
#define CGS_PRIVATE_H

#include <CoreGraphics/CoreGraphics.h>

// Private CoreGraphics (SkyLight) entry points. They are not in any public header,
// but they are the only way for a background application to take over the cursor.
// Declaring the prototypes is enough; the symbols resolve out of CoreGraphics at
// link time. If a future macOS drops them the app fails to launch rather than
// silently leaving the pointer in a bad state.
typedef int CGSConnectionID;

extern CGSConnectionID CGSMainConnectionID(void);

extern CGError CGSSetConnectionProperty(CGSConnectionID cid,
                                        CGSConnectionID targetCID,
                                        CFStringRef key,
                                        CFTypeRef value);

#endif
