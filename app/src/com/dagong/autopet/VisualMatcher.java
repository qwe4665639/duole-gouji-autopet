package com.dagong.autopet;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

public final class VisualMatcher {

    public static final class Match {
        public final int x;
        public final int y;
        public final double error;

        public Match(int x, int y, double error) {
            this.x = x;
            this.y = y;
            this.error = error;
        }
    }

    public static final class Template {
        final int width;
        final int height;
        final int[] dx;
        final int[] dy;
        final int[] red;
        final int[] green;
        final int[] blue;

        public Template(int width, int height, int[] pixels) {
            this.width = width;
            this.height = height;
            List<Integer> valid = new ArrayList<Integer>();
            for (int i = 0; i < pixels.length; i++) {
                if ((pixels[i] >>> 24) > 200) {
                    valid.add(Integer.valueOf(i));
                }
            }
            Collections.shuffle(valid, new Random(1729L));
            int n = Math.min(240, valid.size());
            this.dx = new int[n];
            this.dy = new int[n];
            this.red = new int[n];
            this.green = new int[n];
            this.blue = new int[n];
            for (int k = 0; k < n; k++) {
                int idx = valid.get(k).intValue();
                int p = pixels[idx];
                this.dx[k] = idx % width;
                this.dy[k] = idx / width;
                this.red[k] = (p >> 16) & 0xFF;
                this.green[k] = (p >> 8) & 0xFF;
                this.blue[k] = p & 0xFF;
            }
        }
    }

    public static Match find(int[] pixels, int width, int height, Template template,
                             int x0, int y0, int x1, int y1, double tolerance) {
        int maxX = Math.min(width, x1) - template.width;
        int maxY = Math.min(height, y1) - template.height;
        Match best = null;
        double bestError = tolerance;
        for (int y = Math.max(0, y0); y <= maxY; y++) {
            for (int x = Math.max(0, x0); x <= maxX; x++) {
                int total = 0;
                int n = 0;
                for (int k = 0; k < template.dx.length; k++) {
                    int index = (y + template.dy[k]) * width + x + template.dx[k];
                    int p = pixels[index];
                    total += Math.abs(((p >> 16) & 0xFF) - template.red[k])
                            + Math.abs(((p >> 8) & 0xFF) - template.green[k])
                            + Math.abs((p & 0xFF) - template.blue[k]);
                    n++;
                    if (n == 8 || n == 24 || n == 64) {
                        if ((double) total > (double) (n * 3) * (tolerance + 9.0)) {
                            break;
                        }
                    }
                }
                if (n == template.dx.length) {
                    double error = (double) total / (n * 3.0);
                    if (error < bestError) {
                        best = new Match(x + template.width / 2, y + template.height / 2, error);
                        bestError = error;
                    }
                }
            }
        }
        return best;
    }
}
