class_name Tone
extends RefCounted

## turns a buffer of samples into an AudioStreamWAV, for anything that synthesises its own sound
## instead of shipping a file. the laser is the one that does: the length of a charge then comes
## from the same number as the charge itself, and there is no asset to import, to mis-import, or
## to go missing.

const RATE := 22050


static func wav(samples: PackedFloat32Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	return stream
