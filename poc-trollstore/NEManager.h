#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void POCNEInstallAndStart(void (^completion)(NSString *status));
void POCNEStop(void (^completion)(NSString *status));
void POCNESendPing(void (^completion)(NSString *status));

#ifdef __cplusplus
}
#endif
