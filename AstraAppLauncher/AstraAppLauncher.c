#include <TargetConditionals.h>

#if TARGET_OS_OSX
extern void AstraBrowserMain(void);

int main(int argc, char *argv[]) {
	(void)argc;
	(void)argv;
	AstraBrowserMain();
	return 0;
}
#endif
