// TalkFlow ORT C Bridge
// 提供简化的 ONNX Runtime C API 封装供 Swift 调用
// 通过 Bridging Header 引入

#ifndef TalkFlowORTBridge_h
#define TalkFlowORTBridge_h

#ifdef __cplusplus
extern "C" {
#endif

#include "include/onnxruntime_c_api.h"

// ---- 类型 ----
typedef const struct OrtApi* OrtApiPtr;
typedef struct OrtEnv* OrtEnvHandle;
typedef struct OrtSession* OrtSessionHandle;
typedef struct OrtMemoryInfo* OrtMemInfoHandle;
typedef struct OrtValue* OrtValueHandle;
typedef struct OrtStatus* OrtStatusHandle;

// ---- API ----
OrtStatusHandle TalkFlowOrtInit(const char* modelPath, OrtEnvHandle* envOut, OrtSessionHandle* sessionOut, OrtMemInfoHandle* memInfoOut);
OrtStatusHandle TalkFlowOrtCreateFloatTensor(const float* data, int64_t* shape, int numDims, OrtMemInfoHandle memInfo, OrtValueHandle* tensorOut);
OrtStatusHandle TalkFlowOrtCreateInt32Tensor(const int32_t* data, int64_t* shape, int numDims, OrtMemInfoHandle memInfo, OrtValueHandle* tensorOut);
OrtStatusHandle TalkFlowOrtRun(OrtSessionHandle session, const char** inputNames, const OrtValue* const* inputs, int numInputs, const char** outputNames, int numOutputs, OrtValueHandle* outputs);
float* TalkFlowOrtGetFloatData(OrtValueHandle tensor);
void TalkFlowOrtReleaseValue(OrtValueHandle v);
void TalkFlowOrtReleaseEnv(OrtEnvHandle e);
void TalkFlowOrtReleaseSession(OrtSessionHandle s);
void TalkFlowOrtReleaseMemInfo(OrtMemInfoHandle m);

#ifdef __cplusplus
}
#endif

#endif
