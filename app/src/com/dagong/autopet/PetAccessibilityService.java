package com.dagong.autopet;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.AssetManager;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ColorSpace;
import android.graphics.Path;
import android.graphics.Point;
import android.graphics.drawable.GradientDrawable;
import android.hardware.HardwareBuffer;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.Display;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.InputStream;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class PetAccessibilityService extends AccessibilityService {

    public static final String GAME = "com.k7k7.goujihd";

    public static PetAccessibilityService instance;

    private boolean busy;
    private VisualMatcher.Template agreeTemplate;
    private VisualMatcher.Template claimTemplate;
    private VisualMatcher.Template clockTemplate;
    private final AutoFlow flow;
    private int generation;
    private final Handler handler;
    private LinearLayout overlay;
    private boolean panelOpen;
    private WindowManager.LayoutParams params;
    private VisualMatcher.Template petHomeTemplate;
    private VisualMatcher.Template petWorkTemplate;
    private VisualMatcher.Template reloginTemplate;
    private VisualMatcher.Template signinTemplate;
    private VisualMatcher.Template wechatTemplate;
    private boolean running;
    private int savedX;
    private int savedY;
    private final Runnable scan;
    private boolean settingsVisible;
    private String status;
    private TextView statusView;
    private VisualMatcher.Template work2Template;
    private WindowManager wm;
    private final ExecutorService worker;

    public PetAccessibilityService() {
        this.handler = new Handler(Looper.getMainLooper());
        this.worker = Executors.newSingleThreadExecutor();
        this.flow = new AutoFlow();
        this.scan = () -> scan();
        this.status = "已暂停";
        this.savedX = -1;
        this.savedY = 340;
    }

    public static final class Observation {
        VisualMatcher.Match relogin;
        VisualMatcher.Match signin;
        VisualMatcher.Match agree;
        VisualMatcher.Match wechat;
        VisualMatcher.Match petHome;
        VisualMatcher.Match petWork;
        VisualMatcher.Match work2;
        VisualMatcher.Match clock;
        VisualMatcher.Match claim;
        int width;
        int height;
        boolean landscape;

        private Observation() {
        }
    }

    // ---------------------------------------------------------------- state

    public boolean isRunning() {
        return running;
    }

    public String getStatus() {
        return status;
    }

    public void setSettingsVisible(boolean visible) {
        this.settingsVisible = visible;
    }

    public void showFloating() {
        ensureOverlay();
        collapse();
    }

    public void setRunning(boolean wantRunning) {
        generation++;
        busy = false;
        handler.removeCallbacks(scan);
        running = wantRunning && claimTemplate != null;
        flow.reset();
        setStatus(running ? "寻找宠物界面" : "已暂停");
        ensureOverlay();
        collapse();
        if (running) {
            handler.postDelayed(scan, 1000);
        }
    }

    private void setStatus(String text) {
        if (!status.equals(text)) {
            Log.i("AutoPet", text);
        }
        status = text;
        if (statusView != null) {
            statusView.setText(text);
        }
        if (overlay != null) {
            overlay.setContentDescription("宠物打工控制：" + text);
        }
    }

    // ---------------------------------------------------------- service life

    @Override
    protected void onServiceConnected() {
        instance = this;
        wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        SharedPreferences.Editor editor = getSharedPreferences("pet_config", 0).edit();
        editor.putBoolean("enabled", false);
        editor.apply();
        try {
            reloginTemplate = loadTemplate("relogin.png");
            signinTemplate = loadTemplate("signin_close.png");
            agreeTemplate = loadTemplate("agree_unchecked.png");
            wechatTemplate = loadTemplate("wechat_login.png");
            petHomeTemplate = loadTemplate("pet_home_entry.png");
            petWorkTemplate = loadTemplate("pet_work_entry.png");
            work2Template = loadTemplate("work2.png");
            clockTemplate = loadTemplate("clock.png");
            claimTemplate = loadTemplate("claim.png");
        } catch (Exception e) {
            status = "识别模板加载失败";
            Log.e("AutoPet", "识别模板加载失败", e);
        }
    }

    @Override
    public void onInterrupt() {
        setRunning(false);
        setStatus("无障碍服务被中断，已暂停");
    }

    @Override
    public void onDestroy() {
        instance = null;
        generation++;
        running = false;
        handler.removeCallbacksAndMessages(null);
        removeOverlay();
        worker.shutdownNow();
        super.onDestroy();
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent accessibilityEvent) {
        // event driven work is not needed; the scan loop polls screenshots
    }

    @Override
    public void onConfigurationChanged(Configuration configuration) {
        super.onConfigurationChanged(configuration);
        if (overlay != null) {
            collapse();
        }
    }

    private VisualMatcher.Template loadTemplate(String assetName) throws Exception {
        InputStream in = getAssets().open(assetName);
        try {
            Bitmap bitmap = BitmapFactory.decodeStream(in);
            int w = bitmap.getWidth();
            int h = bitmap.getHeight();
            int[] pixels = new int[w * h];
            bitmap.getPixels(pixels, 0, w, 0, 0, w, h);
            bitmap.recycle();
            return new VisualMatcher.Template(w, h, pixels);
        } finally {
            if (in != null) {
                in.close();
            }
        }
    }

    // ------------------------------------------------------------ scan loop

    private void scan() {
        if (!running || busy) {
            return;
        }
        if (settingsVisible || panelOpen) {
            later(1000);
            return;
        }
        if (!gameForeground()) {
            setStatus("等待游戏回到前台");
            later(2000);
            return;
        }
        final int ticket = generation;
        busy = true;
        getMainExecutor().execute(() -> takeScreenshot(0, getMainExecutor(),
                new TakeScreenshotCallback() {
                    @Override
                    public void onSuccess(ScreenshotResult screenshotResult) {
                        Bitmap bitmap = null;
                        try {
                            Bitmap hardware;
                            try {
                                Bitmap wrapped = Bitmap.wrapHardwareBuffer(
                                        screenshotResult.getHardwareBuffer(),
                                        screenshotResult.getColorSpace());
                                hardware = wrapped;
                                if (wrapped != null) {
                                    bitmap = wrapped.copy(Bitmap.Config.ARGB_8888, false);
                                }
                            } catch (Exception e) {
                                hardware = null;
                                Log.e("AutoPet", "Screenshot conversion", e);
                            }
                            if (hardware != null) {
                                hardware.recycle();
                            }
                            screenshotResult.getHardwareBuffer().close();
                        } catch (Exception e) {
                            Log.e("AutoPet", "Screenshot conversion", e);
                        }
                        try {
                            if (ticket != generation) {
                                return;
                            }
                            if (bitmap == null) {
                                captureFailed(ticket, "无法读取游戏截图");
                                return;
                            }
                            final Bitmap shot = bitmap;
                            // Ownership of the bitmap moves to the worker thread: it is
                            // recycled in the worker's own finally block. Clearing the local
                            // here stops the outer finally from recycling it while the
                            // asynchronous analyze() is still reading its pixels.
                            bitmap = null;
                            worker.execute(() -> {
                                try {
                                    Observation observation = analyze(shot);
                                    handler.post(() -> accept(ticket, observation));
                                } catch (Exception e) {
                                    Log.e("AutoPet", "Visual analysis", e);
                                    handler.post(() -> captureFailed(ticket, "画面识别失败，请重新开始"));
                                } finally {
                                    shot.recycle();
                                }
                            });
                        } finally {
                            if (bitmap != null) {
                                bitmap.recycle();
                            }
                        }
                    }

                    @Override
                    public void onFailure(int errorCode) {
                        if (errorCode == ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT
                                && ticket == generation) {
                            busy = false;
                            later(1000);
                            return;
                        }
                        captureFailed(ticket, "截图权限不可用，请重新开启无障碍服务（" + errorCode + "）");
                    }
                }));
    }

    private void later(long delayMillis) {
        handler.removeCallbacks(scan);
        if (running) {
            handler.postDelayed(scan, delayMillis);
        }
    }

    private boolean canAct(int ticket) {
        return running
                && generation == ticket
                && !settingsVisible
                && !panelOpen
                && gameForeground();
    }

    private boolean gameForeground() {
        // NOTE: do not use getRootInActiveWindow() as the primary test. Our own
        // TYPE_ACCESSIBILITY_OVERLAY floating ball can take the active-window slot, which
        // makes the active root report our own package (and the game window stops being
        // "active"/"focused" at all). Scan the window list instead and accept any visible
        // application window that belongs to the game.
        for (android.view.accessibility.AccessibilityWindowInfo window : getWindows()) {
            if (window.getType() != android.view.accessibility.AccessibilityWindowInfo.TYPE_APPLICATION) {
                continue;
            }
            AccessibilityNodeInfo node = window.getRoot();
            if (node == null) {
                continue;
            }
            CharSequence pkg = node.getPackageName();
            boolean same = GAME.contentEquals(pkg == null ? "" : pkg) && node.isVisibleToUser();
            node.recycle();
            if (same) {
                return true;
            }
        }
        return false;
    }

    private void captureFailed(int ticket, String message) {
        if (ticket != generation) {
            return;
        }
        setRunning(false);
        setStatus(message);
    }

    // -------------------------------------------------------------- analysis

    private Observation analyze(Bitmap bitmap) {
        Observation o = new Observation();
        o.width = bitmap.getWidth();
        o.height = bitmap.getHeight();
        o.landscape = Math.abs(((double) o.width / (double) o.height) - 1.77778) < 0.04;
        if (!o.landscape) {
            return o;
        }
        Bitmap scaled = (o.width == 1600 && o.height == 900)
                ? bitmap
                : Bitmap.createScaledBitmap(bitmap, 1600, 900, true);
        int[] pixels = new int[1600 * 900];
        scaled.getPixels(pixels, 0, 1600, 0, 0, 1600, 900);
        if (scaled != bitmap) {
            scaled.recycle();
        }
        o.relogin = VisualMatcher.find(pixels, 1600, 900, reloginTemplate, 300, 500, 1300, 790, 24.0);
        o.signin = VisualMatcher.find(pixels, 1600, 900, signinTemplate, 1150, 10, 1500, 180, 24.0);
        o.wechat = VisualMatcher.find(pixels, 1600, 900, wechatTemplate, 450, 660, 1180, 800, 24.0);
        if (o.wechat != null) {
            o.agree = VisualMatcher.find(pixels, 1600, 900, agreeTemplate, 250, 760, 950, 870, 24.0);
        }
        o.petHome = VisualMatcher.find(pixels, 1600, 900, petHomeTemplate, 740, 600, 1030, 780, 24.0);
        o.petWork = VisualMatcher.find(pixels, 1600, 900, petWorkTemplate, 0, 380, 220, 580, 24.0);
        o.work2 = VisualMatcher.find(pixels, 1600, 900, work2Template, 380, 380, 1280, 800, 24.0);
        o.clock = VisualMatcher.find(pixels, 1600, 900, clockTemplate, 570, 150, 725, 270, 24.0);
        if (o.petWork != null) {
            o.claim = VisualMatcher.find(pixels, 1600, 900, claimTemplate, 160, 120, 1550, 700, 27.0);
        }
        return o;
    }

    // ------------------------------------------------------- decision making

    private void accept(int ticket, Observation o) {
        if (ticket != generation) {
            return;
        }
        busy = false;
        Log.i("AutoPet", "OBS " + o.width + "x" + o.height
                + " relogin=" + (o.relogin == null ? "-" : String.format("%.1f", o.relogin.error))
                + " signin=" + (o.signin == null ? "-" : String.format("%.1f", o.signin.error))
                + " agree=" + (o.agree == null ? "-" : String.format("%.1f", o.agree.error))
                + " wechat=" + (o.wechat == null ? "-" : String.format("%.1f", o.wechat.error))
                + " petHome=" + (o.petHome == null ? "-" : String.format("%.1f", o.petHome.error))
                + " petWork=" + (o.petWork == null ? "-" : String.format("%.1f", o.petWork.error))
                + " work2=" + (o.work2 == null ? "-" : String.format("%.1f", o.work2.error))
                + " clock=" + (o.clock == null ? "-" : String.format("%.1f", o.clock.error))
                + " claim=" + (o.claim == null ? "-" : String.format("%.1f", o.claim.error)));
        if (!canAct(ticket)) {
            later(1500);
            return;
        }
        if (!o.landscape) {
            setStatus("请使用 1600×900 横屏游戏画面");
            later(3000);
            return;
        }
        AutoFlow.Action decided = flow.next(
                o.relogin != null,
                o.signin != null,
                o.agree != null,
                o.wechat != null,
                o.petHome != null,
                o.petWork != null,
                o.work2 != null,
                o.clock != null,
                o.claim != null,
                SystemClock.elapsedRealtime());
        setStatus(flow.status);
        if (decided == AutoFlow.Action.PAUSE) {
            String previous = status;
            setRunning(false);
            setStatus(previous);
            return;
        }
        VisualMatcher.Match target;
        if (decided == AutoFlow.Action.CLICK_RELOGIN) {
            target = o.relogin;
        } else if (decided == AutoFlow.Action.CLICK_SIGNIN_CLOSE) {
            target = o.signin;
        } else if (decided == AutoFlow.Action.CLICK_AGREE) {
            target = o.agree;
        } else if (decided == AutoFlow.Action.CLICK_WECHAT) {
            target = o.wechat;
        } else if (decided == AutoFlow.Action.CLICK_CLAIM) {
            target = o.claim;
        } else if (decided == AutoFlow.Action.CLICK_WORK2) {
            target = o.work2;
        } else if (decided == AutoFlow.Action.CLICK_PET_WORK) {
            target = o.petWork;
        } else if (decided == AutoFlow.Action.CLICK_PET_HOME) {
            target = o.petHome;
        } else {
            target = null;
        }
        if (target == null) {
            later(o.clock != null ? 10000 : 2000);
            return;
        }
        if (!canAct(ticket)) {
            later(1500);
            return;
        }
        float x = (float) (target.x * o.width) / 1600.0f;
        float y = (float) (target.y * o.height) / 900.0f;
        Path path = new Path();
        path.moveTo(x, y);
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, 80))
                .build();
        busy = true;
        if (!dispatchGesture(gesture, new GestureResultCallback() {
            @Override
            public void onCancelled(GestureDescription gestureDescription) {
                captureFailed(ticket, "点击被中断，已暂停");
            }

            @Override
            public void onCompleted(GestureDescription gestureDescription) {
                if (ticket != generation) {
                    return;
                }
                busy = false;
                later(2000);
            }
        }, handler)) {
            captureFailed(ticket, "系统未接受点击，已暂停");
            return;
        }
        Log.i("AutoPet", "ACTION " + decided + " at " + x + "," + y + " match=" + target.error);
    }

    // -------------------------------------------------------------- overlay

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private Point screenSize() {
        Point point = new Point();
        wm.getDefaultDisplay().getRealSize(point);
        return point;
    }

    private GradientDrawable background(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius((float) dp((float) radiusDp));
        return drawable;
    }

    private void ensureOverlay() {
        if (overlay != null) {
            return;
        }
        LinearLayout layout = new LinearLayout(this);
        this.overlay = layout;
        layout.setOrientation(LinearLayout.VERTICAL);
        // flags 2024 = 0x7E8. The reconstructed value 2032 (0x7F0) had FLAG_NOT_TOUCHABLE
        // (0x10) set, so the floating ball could never receive a touch: tapping did nothing
        // and dragging did nothing. It also lacked FLAG_NOT_FOCUSABLE (0x8), which is why the
        // overlay kept stealing the focused window and broke the game-foreground test.
        // 2024 keeps every other flag of the original and clears/sets exactly those two bits.
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                dp(48.0f), dp(48.0f), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY, 2024, -3);
        this.params = lp;
        lp.gravity = 51;
        Point screen = screenSize();
        if (savedX < 0) {
            savedX = screen.x - dp(60.0f);
        }
        lp.x = savedX;
        lp.y = savedY;
        wm.addView(overlay, lp);
    }

    private void collapse() {
        if (overlay == null) {
            return;
        }
        panelOpen = false;
        statusView = null;
        overlay.removeAllViews();
        overlay.setPadding(0, 0, 0, 0);
        overlay.setBackground(background(running ? 0xFF26764D : 0xFF596970, 24));
        TextView dot = new TextView(this);
        dot.setText("工");
        dot.setTextSize(19.0f);
        dot.setTextColor(-1);
        dot.setGravity(17);
        overlay.addView(dot, new LinearLayout.LayoutParams(dp(48.0f), dp(48.0f)));
        params.width = dp(48.0f);
        params.height = dp(48.0f);
        Point screen = screenSize();
        savedX = Math.max(0, Math.min(savedX, screen.x - params.width));
        savedY = Math.max(0, Math.min(savedY, screen.y - params.height));
        params.x = savedX;
        params.y = savedY;
        wm.updateViewLayout(overlay, params);
        dot.setOnTouchListener(new View.OnTouchListener() {
            private float initialX;
            private float initialY;
            private boolean moved;
            private int startX;
            private int startY;

            @Override
            public boolean onTouch(View view, MotionEvent event) {
                int action = event.getAction();
                if (action == MotionEvent.ACTION_DOWN) {
                    initialX = event.getRawX();
                    initialY = event.getRawY();
                    startX = params.x;
                    startY = params.y;
                    moved = false;
                    return true;
                }
                if (action == MotionEvent.ACTION_MOVE) {
                    float dx = event.getRawX() - initialX;
                    float dy = event.getRawY() - initialY;
                    if (Math.abs(dx) + Math.abs(dy) > (float) dp(6.0f)) {
                        moved = true;
                    }
                    if (moved) {
                        Point screen = screenSize();
                        params.x = Math.max(0, Math.min(startX + (int) dx, screen.x - dp(48.0f)));
                        params.y = Math.max(0, Math.min(startY + (int) dy, screen.y - dp(48.0f)));
                        wm.updateViewLayout(overlay, params);
                        savedX = params.x;
                        savedY = params.y;
                    }
                    return true;
                }
                if (action == MotionEvent.ACTION_UP && !moved) {
                    expand();
                }
                return true;
            }
        });
    }

    private void expand() {
        if (overlay == null) {
            return;
        }
        panelOpen = true;
        overlay.removeAllViews();
        overlay.setPadding(dp(12.0f), dp(8.0f), dp(12.0f), dp(8.0f));
        overlay.setBackground(background(0xFFF5F8F4, 14));
        TextView title = new TextView(this);
        title.setText("宠物自动打工");
        title.setTextSize(18.0f);
        title.setTextColor(0xFF234735);
        overlay.addView(title);
        statusView = new TextView(this);
        statusView.setText(status);
        statusView.setTextSize(13.0f);
        statusView.setTextColor(0xFF52665B);
        overlay.addView(statusView);
        panelButton(running ? "暂停运行" : "开始运行", () -> setRunning(!running));
        LinearLayout row = new LinearLayout(this);
        Button collapseButton = new Button(this);
        collapseButton.setText("收起");
        collapseButton.setOnClickListener(v -> collapse());
        row.addView(collapseButton,
                new LinearLayout.LayoutParams(0, dp(44.0f), 1.0f));
        Button settingsButton = new Button(this);
        settingsButton.setText("设置");
        settingsButton.setOnClickListener(view -> {
            collapse();
            startActivity(new Intent(this, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        });
        row.addView(settingsButton, new LinearLayout.LayoutParams(0, dp(44.0f), 1.0f));
        overlay.addView(row);
        panelButton("停止并关闭悬浮球", () -> closeControls());
        params.width = dp(270.0f);
        params.height = -2;
        Point screen = screenSize();
        params.x = Math.max(0, Math.min(savedX, screen.x - params.width));
        params.y = Math.max(0, Math.min(savedY, screen.y - dp(255.0f)));
        wm.updateViewLayout(overlay, params);
    }

    private void panelButton(String text, Runnable action) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        button.setOnClickListener(v -> action.run());
        overlay.addView(button, new LinearLayout.LayoutParams(-1, dp(44.0f)));
    }

    private void removeOverlay() {
        if (overlay != null) {
            wm.removeView(overlay);
            overlay = null;
        }
        statusView = null;
        panelOpen = false;
    }

    public void closeControls() {
        generation++;
        running = false;
        busy = false;
        handler.removeCallbacks(scan);
        setStatus("已停止");
        removeOverlay();
    }
}
