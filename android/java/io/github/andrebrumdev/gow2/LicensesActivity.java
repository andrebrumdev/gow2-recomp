package io.github.andrebrumdev.gow2;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/** "Licenças": FFmpeg's notice and licence, SDL2's licence, and the exact FFmpeg source
 *  tarball the libraries were built from, exportable to Download/ (spec §3.5). */
public class LicensesActivity extends Activity {
    private static final String[] TEXTS = {
        "licenses/ffmpeg/NOTICE.txt",
        "licenses/ffmpeg/COPYING.LGPLv2.1",
        "licenses/ffmpeg/LICENSE.md",
        "licenses/sdl2/LICENSE.txt",
    };
    private static final String TARBALL = "licenses/ffmpeg/ffmpeg-8.1.3.tar.xz";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        Button export = new Button(this);
        export.setText("Exportar código-fonte do FFmpeg");
        export.setOnClickListener(v -> exportSource());
        col.addView(export);
        TextView tv = new TextView(this);
        tv.setTextIsSelectable(true);
        StringBuilder sb = new StringBuilder();
        for (String t : TEXTS) {
            sb.append("==== ").append(t).append(" ====\n\n").append(readAsset(t)).append("\n\n");
        }
        tv.setText(sb.toString());
        col.addView(tv);
        ScrollView sv = new ScrollView(this);
        sv.addView(col);
        setContentView(sv);
        if (getIntent() != null && getIntent().getBooleanExtra("export", false)) {
            exportSource();   /* tools/android: am start ... --ez export true (the D0 acceptance check) */
        }
    }

    private String readAsset(String name) {
        try (InputStream in = getAssets().open(name)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] b = new byte[16384];
            int n;
            while ((n = in.read(b)) > 0) {
                out.write(b, 0, n);
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "(" + name + " ausente: " + e + ")";
        }
    }

    private void exportSource() {
        ContentValues cv = new ContentValues();
        /* a unique, plain name (no " (1)" suffixes): ffmpeg-8.1.3-<epoch ms>.tar.xz */
        cv.put(MediaStore.Downloads.DISPLAY_NAME, "ffmpeg-8.1.3-" + System.currentTimeMillis() + ".tar.xz");
        cv.put(MediaStore.Downloads.MIME_TYPE, "application/x-xz");
        ContentResolver cr = getContentResolver();
        Uri uri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
        if (uri == null) {
            Toast.makeText(this, "Falha ao criar o arquivo em Download", Toast.LENGTH_LONG).show();
            return;
        }
        try (InputStream in = getAssets().open(TARBALL); OutputStream out = cr.openOutputStream(uri)) {
            byte[] b = new byte[1 << 16];
            int n;
            while ((n = in.read(b)) > 0) {
                out.write(b, 0, n);
            }
            Toast.makeText(this, "Código-fonte do FFmpeg salvo em Download/", Toast.LENGTH_LONG).show();
        } catch (Exception e) {
            Toast.makeText(this, "Falha ao exportar: " + e, Toast.LENGTH_LONG).show();
        }
    }
}
