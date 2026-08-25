package mods

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
	"strings"

	mp3 "github.com/hajimehoshi/go-mp3"
)

func decodeAudioToPCM(data []byte, filename string) ([]byte, uint32, error) {
	lower := strings.ToLower(filename)
	var (
		pcm  []byte
		rate uint32
		err  error
	)
	switch {
	case strings.HasSuffix(lower, ".wav"):
		pcm, rate, err = decodeWAV(data)
	case strings.HasSuffix(lower, ".mp3"):
		pcm, rate, err = decodeMP3(data)
	default:
		if len(data) >= 12 && string(data[0:4]) == "RIFF" && string(data[8:12]) == "WAVE" {
			pcm, rate, err = decodeWAV(data)
		} else if len(data) >= 3 && (string(data[0:3]) == "ID3" || (data[0] == 0xFF && (data[1]&0xE0) == 0xE0)) {
			pcm, rate, err = decodeMP3(data)
		} else {
			return nil, 0, errors.New("unsupported audio type (use .mp3 or .wav)")
		}
	}
	if err != nil {
		return nil, 0, err
	}
	return normalizePCM16(pcm), rate, nil
}

func decodeMP3(data []byte) ([]byte, uint32, error) {
	dec, err := mp3.NewDecoder(bytes.NewReader(data))
	if err != nil {
		return nil, 0, fmt.Errorf("mp3 decode: %w", err)
	}
	raw, err := io.ReadAll(dec)
	if err != nil {
		return nil, 0, fmt.Errorf("mp3 read: %w", err)
	}
	srcRate := dec.SampleRate()
	// go-mp3 always outputs stereo 16-bit LE; Vector needs mono.
	mono := stereoToMono(raw)
	target := pickRobotRate(srcRate)
	out := resamplePCM16(mono, srcRate, target)
	return out, uint32(target), nil
}

func stereoToMono(stereo []byte) []byte {
	if len(stereo) < 4 {
		return stereo
	}
	frames := len(stereo) / 4
	out := make([]byte, frames*2)
	for i := 0; i < frames; i++ {
		l := int16(binary.LittleEndian.Uint16(stereo[i*4:]))
		r := int16(binary.LittleEndian.Uint16(stereo[i*4+2:]))
		m := int16((int32(l) + int32(r)) / 2)
		binary.LittleEndian.PutUint16(out[i*2:], uint16(m))
	}
	return out
}

func decodeWAV(data []byte) ([]byte, uint32, error) {
	if len(data) < 44 {
		return nil, 0, errors.New("wav too small")
	}
	if string(data[0:4]) != "RIFF" || string(data[8:12]) != "WAVE" {
		return nil, 0, errors.New("not a wav file")
	}
	offset := 12
	var (
		audioFormat   uint16
		numChannels   uint16
		sampleRate    uint32
		bitsPerSample uint16
		pcmData       []byte
	)
	for offset+8 <= len(data) {
		chunkID := string(data[offset : offset+4])
		chunkSize := int(binary.LittleEndian.Uint32(data[offset+4 : offset+8]))
		offset += 8
		if offset+chunkSize > len(data) {
			chunkSize = len(data) - offset
		}
		chunk := data[offset : offset+chunkSize]
		switch chunkID {
		case "fmt ":
			if len(chunk) < 16 {
				return nil, 0, errors.New("invalid wav fmt chunk")
			}
			audioFormat = binary.LittleEndian.Uint16(chunk[0:2])
			numChannels = binary.LittleEndian.Uint16(chunk[2:4])
			sampleRate = binary.LittleEndian.Uint32(chunk[4:8])
			bitsPerSample = binary.LittleEndian.Uint16(chunk[14:16])
		case "data":
			pcmData = chunk
		}
		offset += chunkSize
		if chunkSize%2 == 1 {
			offset++
		}
	}
	if pcmData == nil {
		return nil, 0, errors.New("wav missing data chunk")
	}
	if audioFormat != 1 {
		return nil, 0, errors.New("wav must be PCM (format 1)")
	}
	if bitsPerSample != 16 {
		return nil, 0, errors.New("wav must be 16-bit")
	}
	mono := pcmData
	if numChannels == 2 {
		mono = stereoToMono(pcmData)
	} else if numChannels != 1 {
		return nil, 0, errors.New("wav must be mono or stereo")
	}
	target := pickRobotRate(int(sampleRate))
	out := resamplePCM16(mono, int(sampleRate), target)
	return out, uint32(target), nil
}

func pickRobotRate(srcRate int) int {
	if srcRate >= 8000 && srcRate <= 16025 {
		return srcRate
	}
	// Prefer 16000 for common media rates (44.1/48k).
	return 16000
}

func sampleAt(in []byte, inSamples, idx int) float64 {
	if idx < 0 {
		idx = 0
	}
	if idx >= inSamples {
		idx = inSamples - 1
	}
	return float64(int16(binary.LittleEndian.Uint16(in[idx*2:])))
}

// Cubic hermite resampling — much cleaner than linear for 44.1k→16k.
func resamplePCM16(in []byte, srcRate, dstRate int) []byte {
	if srcRate <= 0 || dstRate <= 0 || len(in) < 2 {
		return in
	}
	if srcRate == dstRate {
		return in
	}
	inSamples := len(in) / 2
	outSamples := int(float64(inSamples) * float64(dstRate) / float64(srcRate))
	if outSamples < 1 {
		outSamples = 1
	}
	out := make([]byte, outSamples*2)
	for i := 0; i < outSamples; i++ {
		srcPos := float64(i) * float64(srcRate) / float64(dstRate)
		i1 := int(math.Floor(srcPos))
		mu := srcPos - float64(i1)
		y0 := sampleAt(in, inSamples, i1-1)
		y1 := sampleAt(in, inSamples, i1)
		y2 := sampleAt(in, inSamples, i1+1)
		y3 := sampleAt(in, inSamples, i1+2)
		s := hermite(y0, y1, y2, y3, mu)
		if s > 32767 {
			s = 32767
		} else if s < -32768 {
			s = -32768
		}
		binary.LittleEndian.PutUint16(out[i*2:], uint16(int16(s)))
	}
	return out
}

func hermite(y0, y1, y2, y3, mu float64) float64 {
	mu2 := mu * mu
	a0 := -0.5*y0 + 1.5*y1 - 1.5*y2 + 0.5*y3
	a1 := y0 - 2.5*y1 + 2*y2 - 0.5*y3
	a2 := -0.5*y0 + 0.5*y2
	a3 := y1
	return a0*mu*mu2 + a1*mu2 + a2*mu + a3
}

func normalizePCM16(pcm []byte) []byte {
	if len(pcm) < 2 {
		return pcm
	}
	n := len(pcm) / 2
	var peak int32
	for i := 0; i < n; i++ {
		s := int32(int16(binary.LittleEndian.Uint16(pcm[i*2:])))
		if s < 0 {
			s = -s
		}
		if s > peak {
			peak = s
		}
	}
	if peak < 1024 || peak >= 32000 {
		return pcm
	}
	out := make([]byte, len(pcm))
	scale := 30000.0 / float64(peak)
	for i := 0; i < n; i++ {
		s := float64(int16(binary.LittleEndian.Uint16(pcm[i*2:]))) * scale
		if s > 32767 {
			s = 32767
		} else if s < -32768 {
			s = -32768
		}
		binary.LittleEndian.PutUint16(out[i*2:], uint16(int16(s)))
	}
	return out
}
