package mods

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"strings"

	mp3 "github.com/hajimehoshi/go-mp3"
)

func decodeAudioToPCM(data []byte, filename string) ([]byte, uint32, error) {
	lower := strings.ToLower(filename)
	switch {
	case strings.HasSuffix(lower, ".wav"):
		return decodeWAV(data)
	case strings.HasSuffix(lower, ".mp3"):
		return decodeMP3(data)
	default:
		// sniff
		if len(data) >= 12 && string(data[0:4]) == "RIFF" && string(data[8:12]) == "WAVE" {
			return decodeWAV(data)
		}
		if len(data) >= 3 && (string(data[0:3]) == "ID3" || (data[0] == 0xFF && (data[1]&0xE0) == 0xE0)) {
			return decodeMP3(data)
		}
		return nil, 0, errors.New("unsupported audio type (use .mp3 or .wav)")
	}
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
	target := 16000
	if srcRate >= 8000 && srcRate <= 16025 {
		target = srcRate
	}
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
	target := uint32(16000)
	if sampleRate >= 8000 && sampleRate <= 16025 {
		target = sampleRate
	}
	out := resamplePCM16(mono, int(sampleRate), int(target))
	return out, target, nil
}

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
		i0 := int(srcPos)
		if i0 >= inSamples {
			i0 = inSamples - 1
		}
		i1 := i0 + 1
		if i1 >= inSamples {
			i1 = inSamples - 1
		}
		frac := srcPos - float64(i0)
		s0 := int16(binary.LittleEndian.Uint16(in[i0*2:]))
		s1 := int16(binary.LittleEndian.Uint16(in[i1*2:]))
		s := int16(float64(s0)*(1-frac) + float64(s1)*frac)
		binary.LittleEndian.PutUint16(out[i*2:], uint16(s))
	}
	return out
}
