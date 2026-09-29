package io.github.andrebrumdev.gow2;

import android.content.Intent;
import android.os.Bundle;
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
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        getWindow().setAttributes(lp);
    }
}
