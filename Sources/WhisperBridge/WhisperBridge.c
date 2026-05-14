#include "WhisperBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "whisper.h"

typedef struct {
    int sample_rate;
    int channels;
    int bits_per_sample;
    int16_t *samples;
    size_t sample_count;
} wav_data;

static uint32_t read_u32_le(const unsigned char *p) {
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint16_t read_u16_le(const unsigned char *p) {
    return ((uint16_t)p[0]) | ((uint16_t)p[1] << 8);
}

static int read_wav_i16(const char *path, wav_data *out) {
    memset(out, 0, sizeof(*out));

    FILE *f = fopen(path, "rb");
    if (!f) {
        return 0;
    }

    unsigned char header[12];
    if (fread(header, 1, sizeof(header), f) != sizeof(header)) {
        fclose(f);
        return 0;
    }
    if (memcmp(header, "RIFF", 4) != 0 || memcmp(header + 8, "WAVE", 4) != 0) {
        fclose(f);
        return 0;
    }

    int saw_fmt = 0;
    int saw_data = 0;
    uint16_t audio_format = 0;
    uint16_t channels = 0;
    uint32_t sample_rate = 0;
    uint16_t bits_per_sample = 0;
    int16_t *samples = NULL;
    size_t sample_count = 0;

    while (!feof(f)) {
        unsigned char chunk_header[8];
        if (fread(chunk_header, 1, sizeof(chunk_header), f) != sizeof(chunk_header)) {
            break;
        }

        uint32_t chunk_size = read_u32_le(chunk_header + 4);
        long chunk_start = ftell(f);

        if (memcmp(chunk_header, "fmt ", 4) == 0) {
            unsigned char fmt[40];
            size_t to_read = chunk_size < sizeof(fmt) ? chunk_size : sizeof(fmt);
            if (fread(fmt, 1, to_read, f) != to_read || to_read < 16) {
                fclose(f);
                return 0;
            }
            audio_format = read_u16_le(fmt);
            channels = read_u16_le(fmt + 2);
            sample_rate = read_u32_le(fmt + 4);
            bits_per_sample = read_u16_le(fmt + 14);
            saw_fmt = 1;
        } else if (memcmp(chunk_header, "data", 4) == 0) {
            if (!saw_fmt || audio_format != 1 || bits_per_sample != 16 || channels < 1) {
                fclose(f);
                return 0;
            }

            size_t total_i16 = chunk_size / sizeof(int16_t);
            int16_t *raw = (int16_t *)malloc(total_i16 * sizeof(int16_t));
            if (!raw) {
                fclose(f);
                return 0;
            }
            if (fread(raw, sizeof(int16_t), total_i16, f) != total_i16) {
                free(raw);
                fclose(f);
                return 0;
            }

            sample_count = total_i16 / channels;
            samples = (int16_t *)malloc(sample_count * sizeof(int16_t));
            if (!samples) {
                free(raw);
                fclose(f);
                return 0;
            }

            if (channels == 1) {
                memcpy(samples, raw, sample_count * sizeof(int16_t));
            } else {
                for (size_t i = 0; i < sample_count; i++) {
                    int sum = 0;
                    for (uint16_t ch = 0; ch < channels; ch++) {
                        sum += raw[i * channels + ch];
                    }
                    samples[i] = (int16_t)(sum / channels);
                }
            }
            free(raw);
            saw_data = 1;
        }

        long chunk_end = chunk_start + chunk_size + (chunk_size % 2);
        fseek(f, chunk_end, SEEK_SET);
    }

    fclose(f);

    if (!saw_fmt || !saw_data || !samples || sample_rate != 16000) {
        free(samples);
        return 0;
    }

    out->sample_rate = (int)sample_rate;
    out->channels = channels;
    out->bits_per_sample = bits_per_sample;
    out->samples = samples;
    out->sample_count = sample_count;
    return 1;
}

static char *copy_c_string(const char *text) {
    size_t len = strlen(text);
    char *out = (char *)malloc(len + 1);
    if (!out) {
        return NULL;
    }
    memcpy(out, text, len + 1);
    return out;
}

static char *error_string(const char *message) {
    const char *prefix = "ERROR: ";
    size_t len = strlen(prefix) + strlen(message);
    char *out = (char *)malloc(len + 1);
    if (!out) {
        return NULL;
    }
    strcpy(out, prefix);
    strcat(out, message);
    return out;
}

char *lw_transcribe_wav_file(const char *model_path, const char *wav_path, const char *language) {
    wav_data wav;
    if (!read_wav_i16(wav_path, &wav)) {
        return error_string("failed to read 16 kHz 16-bit PCM WAV");
    }

    float *pcm = (float *)malloc(wav.sample_count * sizeof(float));
    if (!pcm) {
        free(wav.samples);
        return error_string("failed to allocate PCM buffer");
    }
    for (size_t i = 0; i < wav.sample_count; i++) {
        pcm[i] = (float)wav.samples[i] / 32768.0f;
    }
    free(wav.samples);

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;
    struct whisper_context *ctx = whisper_init_from_file_with_params(model_path, cparams);
    if (!ctx) {
        free(pcm);
        return error_string("failed to load whisper model");
    }

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.translate = false;
    params.language = language && strlen(language) > 0 ? language : "en";
    params.n_threads = 4;

    int rc = whisper_full(ctx, params, pcm, (int)wav.sample_count);
    free(pcm);
    if (rc != 0) {
        whisper_free(ctx);
        return error_string("whisper transcription failed");
    }

    int n_segments = whisper_full_n_segments(ctx);
    size_t total = 1;
    for (int i = 0; i < n_segments; i++) {
        const char *segment = whisper_full_get_segment_text(ctx, i);
        total += strlen(segment) + 1;
    }

    char *result = (char *)calloc(total, 1);
    if (!result) {
        whisper_free(ctx);
        return error_string("failed to allocate result");
    }

    for (int i = 0; i < n_segments; i++) {
        const char *segment = whisper_full_get_segment_text(ctx, i);
        if (i > 0 && strlen(result) > 0) {
            strcat(result, " ");
        }
        strcat(result, segment);
    }

    whisper_free(ctx);
    return result;
}

void lw_free_string(char *ptr) {
    free(ptr);
}
