package com.dagong.autopet;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.view.Gravity;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends android.app.Activity {

    private static final String PREF = "pet_config";

    private final Handler handler = new Handler();

    private final Runnable refresh = new Runnable() {
        @Override
        public void run() {
            PetAccessibilityService s = PetAccessibilityService.instance;
            if (s != null) {
                s.setSettingsVisible(true);
                status.setText("服务已开启 · " + s.getStatus());
            } else {
                status.setText("请先开启「宠物自动打工服务」");
            }
            handler.postDelayed(this, 750);
        }
    };

    private TextView status;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(12), dp(20), dp(14));

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);

        TextView title = new TextView(this);
        title.setText("宠物自动打工 2.1");
        title.setTextSize(21);
        title.setTextColor(0xFF234735);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(45), 1f));

        Button close = new Button(this);
        close.setText("关闭");
        close.setOnClickListener(v -> finish());
        header.addView(close, new LinearLayout.LayoutParams(dp(78), dp(14)));

        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content);

        status = text("请先开启无障碍服务", 14);
        content.addView(status);

        content.addView(text("掉线自动重连并回到宠物家园。有奖励先领奖，宠物打工中就等它结束，否则直接开工。固定选择园艺师（「2开工」）。\n打工时等待奖励出现，位置变化也会重新寻找。", 15));

        button(content, "1 · 开启无障碍服务", () -> startActivity(new Intent("android.settings.ACCESSIBILITY_SETTINGS")));
        button(content, "2 · 开始并返回游戏", () -> {
            PetAccessibilityService s = service();
            if (s == null) {
                return;
            }
            s.setRunning(true);
            returnToGame();
        });
        button(content, "只缩成悬浮球（暂不运行）", () -> {
            PetAccessibilityService s = service();
            if (s == null) {
                return;
            }
            s.setRunning(false);
            returnToGame();
        });
        button(content, "停止并关闭悬浮球", () -> {
            PetAccessibilityService s = PetAccessibilityService.instance;
            if (s != null) {
                s.closeControls();
            }
            finish();
        });

        content.addView(text("点悬浮球展开控制，拖动可换位置。\n灰色表示暂停，绿色表示运行；展开控制时暂停识别。\n适用：多乐够级宠物界面，1600×900 横屏，Android 11 及以上。", 12));

        root.addView(scroll, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);

        int screenWidth = getResources().getDisplayMetrics().widthPixels;
        int screenHeight = getResources().getDisplayMetrics().heightPixels;
        getWindow().setLayout(Math.min(dp(450), screenWidth - dp(24)), Math.min(dp(500), screenHeight - dp(70)));
        getWindow().setGravity(Gravity.CENTER);
    }

    private TextView text(String value, int size) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(0xFF444444);
        view.setPadding(0, dp(6), 0, dp(6));
        return view;
    }

    private void button(LinearLayout parent, String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(v -> action.run());
        parent.addView(button, new LinearLayout.LayoutParams(-1, dp(48)));
    }

    private PetAccessibilityService service() {
        if (PetAccessibilityService.instance == null) {
            Toast.makeText(this, "请先在无障碍设置里开启服务", Toast.LENGTH_SHORT).show();
        }
        return PetAccessibilityService.instance;
    }

    private void returnToGame() {
        Intent intent = getPackageManager().getLaunchIntentForPackage("com.k7k7.goujihd");
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } else {
            Toast.makeText(this, "请切换到游戏的宠物界面", Toast.LENGTH_SHORT).show();
        }
        finish();
    }

    @Override
    protected void onResume() {
        super.onResume();
        handler.post(refresh);
    }

    @Override
    protected void onPause() {
        handler.removeCallbacks(refresh);
        super.onPause();
    }

    @Override
    protected void onStop() {
        if (PetAccessibilityService.instance != null) {
            PetAccessibilityService.instance.setSettingsVisible(false);
        }
        super.onStop();
    }
}
