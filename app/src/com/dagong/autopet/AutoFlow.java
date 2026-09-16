package com.dagong.autopet;


public final class AutoFlow {
    public enum Action { NONE, CLICK_RELOGIN, CLICK_SIGNIN_CLOSE, CLICK_AGREE, CLICK_WECHAT, CLICK_CLAIM, CLICK_WORK2, CLICK_PET_WORK, CLICK_PET_HOME, PAUSE }
    private static final long WATCHDOG_MILLIS = 45000L;
    private int stage;
    private long lastProgressAt;
    private boolean armed;
    private boolean agreeTicked;
    public String status = "开始运行";
    public void reset() { stage = 0; armed = false; agreeTicked = false; status = "开始运行"; }
    public Action next(boolean relogin, boolean signin, boolean agree, boolean wechat, boolean petHome, boolean petWork, boolean work2, boolean clock, boolean claim, long now) {
        if (!armed) { armed = true; lastProgressAt = now; }
        // Leaving the login screen re-arms the one-shot agreement tick. The checkbox is a
        // toggle and its "unticked" template still matches the ticked state well inside the
        // match tolerance, so without this latch the script would tick and untick it forever
        // and never reach the 微信登录 button.
        if (!wechat) { agreeTicked = false; }
        if (relogin) { stage = 0; lastProgressAt = now; status = "检测到掉线弹窗，正在重新登录"; return Action.CLICK_RELOGIN; }
        if (signin) { stage = 0; lastProgressAt = now; status = "关闭签到面板"; return Action.CLICK_SIGNIN_CLOSE; }
        if (wechat && agree && !agreeTicked) { agreeTicked = true; stage = 0; lastProgressAt = now; status = "勾选用户协议"; return Action.CLICK_AGREE; }
        if (wechat) { stage = 0; lastProgressAt = now; status = "检测到登录界面，点击「微信登录」"; return Action.CLICK_WECHAT; }
        if (claim && petWork) { lastProgressAt = now; status = "领取一个可领取奖励"; return Action.CLICK_CLAIM; }
        if (clock) { stage = 0; lastProgressAt = now; status = "打工中，等待倒计时结束"; return Action.NONE; }
        if (work2) {
            lastProgressAt = now;
            if (stage == 0) { stage = 1; status = "选择园艺师，点击「2开工」"; return Action.CLICK_WORK2; }
            if (stage == 1) { stage = 2; status = "确认开工弹窗，再次点击「2开工」"; return Action.CLICK_WORK2; }
            stage = 2; status = "等待打工倒计时出现"; return Action.NONE;
        }
        if (petWork) { stage = 0; lastProgressAt = now; status = "打开宠物打工"; return Action.CLICK_PET_WORK; }
        if (petHome) { stage = 0; lastProgressAt = now; status = "进入宠物家园"; return Action.CLICK_PET_HOME; }
        if (now - lastProgressAt > WATCHDOG_MILLIS) { status = "长时间未识别到可操作画面，已暂停（请检查游戏画面）"; return Action.PAUSE; }
        status = "等待可识别画面…"; return Action.NONE;
    }
}
