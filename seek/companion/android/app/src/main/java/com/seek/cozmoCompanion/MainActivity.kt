package com.seek.cozmoCompanion

import android.os.Bundle
import android.view.MotionEvent
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.seek.cozmoCompanion.databinding.ActivityMainBinding

/**
 * Cozmo-styled shell for Vector.
 *
 * gRPC / SDK session wiring is next — UI + IP entry work now so we can iterate
 * on drive pads against a live robot once certs are hooked up.
 */
class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private var connected = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.connectBtn.setOnClickListener { toggleConnect() }
        bindPad(binding.btnForward, "forward")
        bindPad(binding.btnBack, "back")
        bindPad(binding.btnLeft, "left")
        bindPad(binding.btnRight, "right")
        binding.btnStop.setOnClickListener { drive("stop") }
    }

    private fun toggleConnect() {
        val ip = binding.ipInput.text?.toString()?.trim().orEmpty()
        if (!connected) {
            if (ip.isEmpty()) {
                Toast.makeText(this, "Enter Vector IP from CCIS", Toast.LENGTH_SHORT).show()
                return
            }
            // TODO: open Vector gRPC session (SDK serial/guid/cert from Wire DDL).
            connected = true
            binding.connectBtn.text = getString(R.string.disconnect)
            binding.status.text = "Ready @ $ip — motor RPC not wired yet"
            binding.driveHint.text = "Next build: gRPC DriveWheels / PlayAnimation"
        } else {
            connected = false
            binding.connectBtn.text = getString(R.string.connect)
            binding.status.text = getString(R.string.status_idle)
            binding.driveHint.text = getString(R.string.drive_hint)
        }
    }

    private fun bindPad(view: android.view.View, dir: String) {
        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> drive(dir)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> drive("stop")
            }
            true
        }
    }

    private fun drive(dir: String) {
        if (!connected) {
            Toast.makeText(this, "Connect first", Toast.LENGTH_SHORT).show()
            return
        }
        binding.status.text = "drive:$dir (stub)"
    }
}
