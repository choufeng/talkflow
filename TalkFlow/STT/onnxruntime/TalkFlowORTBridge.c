// TalkFlow ORT C Bridge — 实现
#include "TalkFlowORTBridge.h"
#include <string.h>

static const OrtApi* GetApi(void) {
    return OrtGetApiBase()->GetApi(ORT_API_VERSION);
}

static int64_t shape_product(const int64_t* shape, int n) {
    int64_t p = 1;
    for (int i = 0; i < n; i++) p *= shape[i];
    return p;
}

OrtStatusHandle TalkFlowOrtInit(const char* path, OrtEnvHandle* outEnv, OrtSessionHandle* outSess, OrtMemInfoHandle* outMem) {
    const OrtApi* api = GetApi();
    if (!api) return NULL;

    OrtStatusHandle st = api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "talkflow", outEnv);
    if (st || !*outEnv) return st;

    OrtSessionOptions* opts = NULL;
    st = api->CreateSessionOptions(&opts);
    if (st) { api->ReleaseEnv(*outEnv); return st; }
    api->SetIntraOpNumThreads(opts, 4);
    api->SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_ALL);

    st = api->CreateSession(*outEnv, path, opts, outSess);
    api->ReleaseSessionOptions(opts);
    if (st) { api->ReleaseEnv(*outEnv); return st; }

    st = api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, outMem);
    if (st) { api->ReleaseSession(*outSess); api->ReleaseEnv(*outEnv); }
    return st;
}

OrtStatusHandle TalkFlowOrtCreateFloatTensor(const float* data, int64_t* shape, int n, OrtMemInfoHandle mem, OrtValueHandle* out) {
    return GetApi()->CreateTensorWithDataAsOrtValue(mem, (void*)data, sizeof(float)*shape_product(shape,n), shape, n, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, out);
}

OrtStatusHandle TalkFlowOrtCreateInt32Tensor(const int32_t* data, int64_t* shape, int n, OrtMemInfoHandle mem, OrtValueHandle* out) {
    return GetApi()->CreateTensorWithDataAsOrtValue(mem, (void*)data, sizeof(int32_t)*shape_product(shape,n), shape, n, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32, out);
}

OrtStatusHandle TalkFlowOrtRun(OrtSessionHandle s, const char** inNames, const OrtValue* const* ins, int ni, const char** outNames, int no, OrtValueHandle* outs) {
    return GetApi()->Run(s, NULL, inNames, ins, ni, outNames, no, outs);
}

float* TalkFlowOrtGetFloatData(OrtValueHandle v) {
    float* d = NULL;
    GetApi()->GetTensorMutableData(v, (void**)&d);
    return d;
}

void TalkFlowOrtReleaseValue(OrtValueHandle v) { if(v) GetApi()->ReleaseValue(v); }
void TalkFlowOrtReleaseEnv(OrtEnvHandle e) { if(e) GetApi()->ReleaseEnv(e); }
void TalkFlowOrtReleaseSession(OrtSessionHandle s) { if(s) GetApi()->ReleaseSession(s); }
void TalkFlowOrtReleaseMemInfo(OrtMemInfoHandle m) { if(m) GetApi()->ReleaseMemoryInfo(m); }
