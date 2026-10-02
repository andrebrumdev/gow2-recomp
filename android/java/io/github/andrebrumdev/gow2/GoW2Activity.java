package io.github.andrebrumdev.gow2;

import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

import org.libsdl.app.SDLActivity;

/** God of War II host activity: SDL2's activity with the FFmpeg libraries loaded by name
 *  before libmain.so, and the launch intent's "gow2_args" string extra as SDL_main's argv
 *  (tools/android scripts start probes and gated runs this way; the icon passes nothing). */
public class GoW2Activity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "avutil", "avcodec", "main" };
    }

    @Override
    protected String[] getArguments() {
        Intent i = getIntent();
        String s = i != null ? i.getStringExtra("gow2_args") : null;
        if (s == null || s.trim().isEmpty()) {
            return new String[0];
        }
        return s.trim().split("\\s+");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // landscape only, whatever way the tablet is held (also re-asserted in code: the manifest value alone
        // is not enough on some launchers/multi-window modes)
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        getWindow().setAttributes(lp);
        getWindow().setDecorFitsSystemWindows(false);   // edge to edge: the game draws under the (hidden) bars
        hideSystemBars();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            hideSystemBars();
        }
    }

    /** Immersive fullscreen: no status/navigation bar; a swipe from the edge shows them briefly. */
    private void hideSystemBars() {
        WindowInsetsController c = getWindow().getInsetsController();
        if (c != null) {
            c.hide(WindowInsets.Type.systemBars());
            c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }
}
