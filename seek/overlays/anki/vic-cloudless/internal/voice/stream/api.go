package stream

import (
	"bytes"
	"context"
	"encoding/binary"

	"github.com/digital-dream-labs/vector-cloud/internal/util"

	"github.com/digital-dream-labs/api-clients/chipper"
)

func NewStreamer(ctx context.Context, receiver Receiver, streamSize int, opts ...Option) *Streamer {
	strm := &Streamer{
		byteChan:    make(chan []byte, 32),
		audioStream: make(chan []byte, 10),
		micDone:     make(chan struct{}),
		receiver:    receiver}

	// set default connector before applying options
	strm.opts.connectFn = strm.newChipperConn
	strm.opts.streamOpts = new(chipper.StreamOpts)
	for _, o := range opts {
		o(&strm.opts)
	}

	var cancel context.CancelFunc
	if timeout := strm.opts.streamOpts.Timeout; timeout != 0 {
		strm.ctx, cancel = context.WithTimeout(ctx, timeout)
	} else {
		strm.ctx, cancel = context.WithCancel(ctx)
	}
	strm.cancel = func() {
		strm.closed = true
		cancel()
	}

	go strm.init(streamSize)
	return strm
}

func (strm *Streamer) AddSamples(samples []int16) {
	if strm.opts.checkOpts != nil {
		// no external audio input during connection check
		return
	}
	var buf bytes.Buffer
	binary.Write(&buf, binary.LittleEndian, samples)
	strm.addBytes(buf.Bytes())
}

func (strm *Streamer) AddBytes(bytes []byte) {
	if strm.opts.checkOpts != nil {
		// no external audio input during connection check
		return
	}
	strm.addBytes(bytes)
}

func (strm *Streamer) Close() error {
	strm.signalMicDone()
	strm.cancel()
	var err util.Errors
	if strm.conn != nil {
		err.Append(strm.conn.Close())
	}
	return err.Error()
}

func (strm *Streamer) signalMicDone() {
	if strm.micDone == nil {
		return
	}
	strm.micDoneOnce.Do(func() {
		close(strm.micDone)
	})
}

func (strm *Streamer) CloseSend() error {
	if strm.conn != nil {
		return strm.conn.CloseSend()
	}
	// Seek/local: mic finished. Drain buffered audio into the listen loop
	// WITHOUT canceling the stream context (cancel closes channels while the
	// mic may still push samples, and it skips Vosk FinalResult — which broke
	// "I have a question").
	strm.signalMicDone()
	return nil
}

// SetVerbose enables or disables verbose logging
func SetVerbose(value bool) {
	verbose = value
}
