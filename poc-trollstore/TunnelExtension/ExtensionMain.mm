#import <Foundation/Foundation.h>

extern "C" int NSExtensionMain(int argc, char *argv[]);

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return NSExtensionMain(argc, argv);
    }
}
