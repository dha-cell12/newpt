#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void POCNEInstallAndStart(void (^completion)(NSString *status));
void POCNEStop(void (^completion)(NSString *status));
void POCNEReset(void (^completion)(NSString *status));
void POCNESendPing(void (^completion)(NSString *status));
void POCNESendFilePing(void (^completion)(NSString *status));
void POCNEReadProviderLog(void (^completion)(NSString *status));
void POCNEStatus(void (^completion)(NSString *status));
void POCNESendInjectTap(double xPx, double yPx, double wPx, double hPx, void (^completion)(NSString *status));
void POCNESendSetSenderID(unsigned long long senderID, void (^completion)(NSString *status));
void POCNESendSetVariant(int variant, void (^completion)(NSString *status));

#ifdef __cplusplus
}
#endif
