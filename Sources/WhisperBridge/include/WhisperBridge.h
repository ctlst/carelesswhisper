#ifndef LOCALWHISPER_BRIDGE_H
#define LOCALWHISPER_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

char *lw_transcribe_wav_file(const char *model_path, const char *wav_path, const char *language);
void lw_free_string(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
