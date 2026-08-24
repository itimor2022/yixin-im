<!-- 系统设置页面 -->
<template>
  <div class="settings-page">
    <ElTabs v-model="activeTab" type="border-card">
      <!-- 基本信息 -->
      <ElTabPane label="基本信息" name="basic">
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          您当前是演示管理员，只能查看设置，无法进行修改
        </ElAlert>
        <ElForm
          ref="basicFormRef"
          :model="basicForm"
          :rules="basicFormRules"
          label-width="140px"
          class="max-w-2xl"
        >
          <ElFormItem label="系统名称" prop="system_name">
            <ElInput
              v-model="basicForm.system_name"
              maxlength="50"
              show-word-limit
              placeholder="如：My Admin"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >显示在左侧菜单顶部，留空则使用默认名称，最多 50 个字符</span
            >
          </ElFormItem>
          <ElFormItem label="系统版本" prop="system_version">
            <ElInput
              v-model="basicForm.system_version"
              placeholder="如：1.0.0"
              :disabled="isDemoAdmin"
            />
            <div class="mt-1 flex items-center gap-3 text-xs text-g-400">
              <span
                >客户端“关于”页将直接显示这里配置的系统版本，格式建议：1.0.0 或 1.0.0-beta.1</span
              >
              <ElButton
                v-if="!isDemoAdmin"
                link
                type="primary"
                size="small"
                @click="syncSystemVersionToPlatforms"
              >
                同步到 iOS / Android 版本号
              </ElButton>
            </div>
          </ElFormItem>
          <ElFormItem label="H5 分享/邀请地址" prop="register_base_url">
            <ElInput
              v-model="basicForm.register_base_url"
              placeholder="如：https://h5.example.com/#"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >用于个人名片、邀请朋友等浏览器链接；请填写 H5 域名，不能填写 API 域名，建议以 /#
              结尾以兼容旧版客户端</span
            >
          </ElFormItem>
          <ElDivider content-position="left">客服联系方式</ElDivider>
          <ElFormItem label="在线客服链接" prop="support_online_url">
            <ElInput
              v-model="basicForm.support_online_url"
              placeholder="如：https://kf.example.com"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >客户端帮助页“在线客服”入口会打开该地址；留空则不展示该入口</span
            >
          </ElFormItem>
          <ElFormItem label="QQ 客服号" prop="support_qq">
            <ElInput
              v-model="basicForm.support_qq"
              maxlength="50"
              show-word-limit
              placeholder="如：QQ 客服号"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >客户端帮助页“QQ 客服”入口会复制该号码；留空则不展示该入口</span
            >
          </ElFormItem>
          <ElDivider content-position="left">App版本</ElDivider>
          <ElFormItem label="iOS最新版本" prop="app_version_ios">
            <ElInput
              v-model="basicForm.app_version_ios"
              placeholder="如：1.0.0"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >留空时保存将自动使用“系统版本”，格式如 1.0.0 或 1.0.0-beta.1</span
            >
          </ElFormItem>
          <ElFormItem label="Android最新版本" prop="app_version_android">
            <ElInput
              v-model="basicForm.app_version_android"
              placeholder="如：1.0.0"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >留空时保存将自动使用“系统版本”，格式如 1.0.0 或 1.0.0-beta.1</span
            >
          </ElFormItem>
          <ElFormItem label="iOS最低支持版本" prop="min_supported_version_ios">
            <ElInput
              v-model="basicForm.min_supported_version_ios"
              placeholder="如：5.0.0"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400">低于此版本时才强制跳转 App Store；留空则不强制</span>
          </ElFormItem>
          <ElFormItem label="Android最低支持版本" prop="min_supported_version_android">
            <ElInput
              v-model="basicForm.min_supported_version_android"
              placeholder="如：5.0.0"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400">低于此版本时强制更新；留空则不强制</span>
          </ElFormItem>
          <ElFormItem label="iOS App Store链接" prop="app_update_url_ios">
            <ElInput
              v-model="basicForm.app_update_url_ios"
              placeholder="https://apps.apple.com/..."
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Android下载链接" prop="app_update_url_android">
            <ElInput
              v-model="basicForm.app_update_url_android"
              placeholder="https://example.com/app.apk"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="更新提示信息" prop="app_update_message">
            <ElInput
              v-model="basicForm.app_update_message"
              type="textarea"
              :rows="3"
              maxlength="500"
              show-word-limit
              placeholder="更新内容说明"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400">最多 500 个字符，建议简要说明本次更新内容</span>
          </ElFormItem>
          <ElDivider content-position="left">客户端启动页</ElDivider>
          <ElFormItem label="启用启动页">
            <ElSwitch v-model="basicForm.splash_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400"
              >开启后客户端启动时优先显示后台配置的启动页图片</span
            >
          </ElFormItem>
          <ElFormItem label="启动页图片">
            <div class="flex items-center gap-3">
              <ElUpload
                :action="portalUploadUrl"
                :headers="portalUploadHeaders"
                :show-file-list="false"
                accept="image/*"
                :disabled="!basicForm.splash_enabled || isDemoAdmin"
                :on-success="handleSplashImageUploadSuccess"
              >
                <div
                  class="flex h-24 w-16 cursor-pointer items-center justify-center overflow-hidden rounded border border-dashed border-g-300 bg-g-50"
                >
                  <img
                    v-if="basicForm.splash_image_url"
                    :src="fixImageUrl(basicForm.splash_image_url)"
                    alt="splash"
                    class="h-full w-full object-cover"
                  />
                  <ArtSvgIcon v-else icon="ri:image-add-line" class="text-g-400 text-xl" />
                </div>
              </ElUpload>
              <div class="text-xs text-g-400">
                建议上传 1080x1920 竖图；不上传时仍使用默认 Logo 启动页。
              </div>
            </div>
          </ElFormItem>
          <ElFormItem label="展示时长">
            <ElInputNumber
              v-model="basicForm.splash_duration_ms"
              :min="800"
              :max="8000"
              :step="100"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">毫秒，默认 3000</span>
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingBasic" @click="saveBasicSettings">
              保存设置
            </ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- 音视频接口 -->
      <ElTabPane label="音视频接口" name="rtc">
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          您当前是演示管理员，只能查看设置，无法进行修改。敏感配置已隐藏。
        </ElAlert>
        <ElAlert v-else type="info" :closable="false" show-icon class="mb-4">
          这里用于切换新发起的单聊通话和群会议默认使用 Agora 或 LiveKit，已创建的房间不受切换影响。
        </ElAlert>
        <ElForm :model="featureForm" label-width="180px" class="max-w-2xl">
          <ElFormItem label="默认音视频接口">
            <div class="flex flex-wrap items-center gap-3">
              <ElRadioGroup v-model="featureForm.rtc_provider" :disabled="isDemoAdmin">
                <ElRadio value="agora">Agora</ElRadio>
                <ElRadio value="livekit">LiveKit</ElRadio>
              </ElRadioGroup>
              <ElTag :type="featureForm.rtc_provider === 'livekit' ? 'success' : 'primary'">
                当前：{{ featureForm.rtc_provider === 'livekit' ? 'LiveKit' : 'Agora' }}
              </ElTag>
            </div>
          </ElFormItem>
          <ElDivider content-position="left">Agora 配置</ElDivider>
          <ElFormItem label="启用 Agora">
            <ElSwitch v-model="featureForm.agora_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">保留原声网通话能力</span>
          </ElFormItem>
          <ElFormItem label="Agora App ID">
            <ElInput
              v-model="featureForm.agora_app_id"
              :placeholder="isDemoAdmin ? '******' : '声网控制台获取的 App ID'"
              :disabled="!featureForm.agora_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Agora Certificate">
            <ElInput
              v-model="featureForm.agora_app_certificate"
              :placeholder="isDemoAdmin ? '******' : '声网控制台获取的 App Certificate'"
              type="password"
              :show-password="!isDemoAdmin"
              :disabled="!featureForm.agora_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Agora Token 有效期">
            <ElInputNumber
              v-model="featureForm.agora_token_expire"
              :min="600"
              :max="86400"
              :step="600"
              controls-position="right"
              :disabled="!featureForm.agora_enabled || isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">秒，默认3600秒（1小时）</span>
          </ElFormItem>
          <ElDivider content-position="left">LiveKit 配置</ElDivider>
          <ElFormItem label="启用 LiveKit">
            <ElSwitch v-model="featureForm.livekit_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后可将新通话/会议切换到 LiveKit</span>
          </ElFormItem>
          <ElFormItem label="LiveKit Server URL">
            <ElInput
              v-model="featureForm.livekit_server_url"
              placeholder="wss://livekit.example.com"
              :disabled="!featureForm.livekit_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="LiveKit API Key">
            <ElInput
              v-model="featureForm.livekit_api_key"
              :placeholder="isDemoAdmin ? '******' : 'LiveKit API Key'"
              type="password"
              :show-password="!isDemoAdmin"
              :disabled="!featureForm.livekit_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="LiveKit API Secret">
            <ElInput
              v-model="featureForm.livekit_api_secret"
              :placeholder="isDemoAdmin ? '******' : 'LiveKit API Secret'"
              type="password"
              :show-password="!isDemoAdmin"
              :disabled="!featureForm.livekit_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="LiveKit Token 有效期">
            <ElInputNumber
              v-model="featureForm.livekit_token_expire"
              :min="600"
              :max="86400"
              :step="600"
              controls-position="right"
              :disabled="!featureForm.livekit_enabled || isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">秒，默认3600秒（1小时）</span>
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingRTC" @click="saveRTCSettings">
              保存音视频接口设置
            </ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- 客户端功能 -->
      <ElTabPane label="客户端功能" name="features">
        <!-- 演示管理员提示 -->
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          您当前是演示管理员，只能查看设置，无法进行修改。敏感配置已隐藏。
        </ElAlert>
        <ElForm :model="featureForm" label-width="180px" class="feature-settings-form">
          <section
            class="attachment-menu-panel"
            :class="{
              'attachment-menu-panel--disabled': !featureForm.chat_attachment_menu.enabled
            }"
          >
            <header class="attachment-menu-header">
              <div class="attachment-menu-heading">
                <span class="attachment-menu-heading__icon">
                  <ArtSvgIcon icon="ri:add-circle-line" />
                </span>
                <div>
                  <div class="attachment-menu-heading__meta">聊天工具管理</div>
                  <h3>聊天扩展菜单</h3>
                  <p>配置聊天输入框左侧“+”菜单中的功能入口，不会影响已有消息和业务数据。</p>
                </div>
              </div>
              <div class="attachment-menu-master">
                <div class="attachment-menu-master__text">
                  <strong>{{
                    featureForm.chat_attachment_menu.enabled ? '扩展菜单已启用' : '扩展菜单已停用'
                  }}</strong>
                  <span>
                    {{
                      featureForm.chat_attachment_menu.enabled
                        ? `当前显示 ${attachmentMenuEnabledCount} / 9 项功能`
                        : '客户端将隐藏“+”按钮'
                    }}
                  </span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.enabled"
                  size="large"
                  :disabled="isDemoAdmin"
                />
              </div>
            </header>

            <div class="attachment-menu-grid">
              <article
                class="attachment-menu-item attachment-menu-item--album"
                :class="{ 'is-active': featureForm.chat_attachment_menu.album }"
              >
                <span class="attachment-menu-item__icon"
                  ><ArtSvgIcon icon="ri:image-2-line"
                /></span>
                <div class="attachment-menu-item__content">
                  <strong>相册</strong>
                  <span>选择照片或视频发送</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.album"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--camera"
                :class="{ 'is-active': featureForm.chat_attachment_menu.camera }"
              >
                <span class="attachment-menu-item__icon"
                  ><ArtSvgIcon icon="ri:camera-3-line"
                /></span>
                <div class="attachment-menu-item__content">
                  <strong>摄像头</strong>
                  <span>拍摄照片或视频发送</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.camera"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--call"
                :class="{ 'is-active': featureForm.chat_attachment_menu.call }"
              >
                <span class="attachment-menu-item__icon"
                  ><ArtSvgIcon icon="ri:vidicon-line"
                /></span>
                <div class="attachment-menu-item__content">
                  <strong>音视频通话</strong>
                  <span>私聊显示通话，群聊显示会议</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.call"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--location"
                :class="{ 'is-active': featureForm.chat_attachment_menu.location }"
              >
                <span class="attachment-menu-item__icon"
                  ><ArtSvgIcon icon="ri:map-pin-line"
                /></span>
                <div class="attachment-menu-item__content">
                  <strong>位置</strong>
                  <span>发送当前或选定的位置</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.location"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--packet"
                :class="{ 'is-active': featureForm.chat_attachment_menu.red_packet }"
              >
                <span class="attachment-menu-item__icon"
                  ><ArtSvgIcon icon="ri:red-packet-line"
                /></span>
                <div class="attachment-menu-item__content">
                  <strong>红包</strong>
                  <span>在聊天中发送红包</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.red_packet"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--transfer"
                :class="{ 'is-active': featureForm.chat_attachment_menu.transfer }"
              >
                <span class="attachment-menu-item__icon"
                  ><ArtSvgIcon icon="ri:exchange-dollar-line"
                /></span>
                <div class="attachment-menu-item__content">
                  <strong>转账</strong>
                  <span>仅在私聊会话中显示</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.transfer"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--favorite"
                :class="{ 'is-active': featureForm.chat_attachment_menu.favorite }"
              >
                <span class="attachment-menu-item__icon"><ArtSvgIcon icon="ri:star-line" /></span>
                <div class="attachment-menu-item__content">
                  <strong>收藏</strong>
                  <span>从收藏内容中选择发送</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.favorite"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--file"
                :class="{ 'is-active': featureForm.chat_attachment_menu.file }"
              >
                <span class="attachment-menu-item__icon"><ArtSvgIcon icon="ri:file-3-line" /></span>
                <div class="attachment-menu-item__content">
                  <strong>文件</strong>
                  <span>选择本地文件发送</span>
                </div>
                <ElSwitch
                  v-model="featureForm.chat_attachment_menu.file"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>

              <article
                class="attachment-menu-item attachment-menu-item--burn"
                :class="{ 'is-active': featureForm.burn_after_read_enabled }"
              >
                <span class="attachment-menu-item__icon"><ArtSvgIcon icon="ri:fire-line" /></span>
                <div class="attachment-menu-item__content">
                  <strong>阅后即焚</strong>
                  <span>查看后按规则自动销毁</span>
                </div>
                <ElSwitch
                  v-model="featureForm.burn_after_read_enabled"
                  :disabled="!featureForm.chat_attachment_menu.enabled || isDemoAdmin"
                />
              </article>
            </div>

            <div class="attachment-menu-notice">
              <ArtSvgIcon icon="ri:information-line" />
              <span>关闭阅后即焚后，后端也会忽略旧版本客户端携带的阅后即焚标记。</span>
            </div>
          </section>
          <section class="feature-section-card feature-section-card--keepalive">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"
                ><ArtSvgIcon icon="ri:signal-wifi-line"
              /></span>
              <div>
                <span class="feature-section-header__eyebrow">消息体验</span>
                <h3>消息到达与后台保活</h3>
                <p>统一控制 Android 客户端后台连接策略，适合对消息及时性要求较高的业务。</p>
              </div>
              <ElTag :type="featureForm.force_keep_alive_enabled ? 'success' : 'info'" round>
                {{ featureForm.force_keep_alive_enabled ? '增强保活已开启' : '使用标准策略' }}
              </ElTag>
            </header>
            <div class="feature-setting-grid feature-setting-grid--single">
              <ElFormItem label="全局强制保活">
                <ElSwitch v-model="featureForm.force_keep_alive_enabled" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">
                  开启后将使用更高频心跳、后台重连和前台服务通知，可能略微增加耗电。
                </span>
              </ElFormItem>
            </div>
          </section>

          <section class="feature-section-card feature-section-card--security">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"
                ><ArtSvgIcon icon="ri:shield-user-line"
              /></span>
              <div>
                <span class="feature-section-header__eyebrow">账号策略</span>
                <h3>注册与安全</h3>
                <p>设置用户进入门槛、快捷注册限制以及首次登录前必须完成的资料。</p>
              </div>
            </header>
            <div class="feature-setting-grid">
              <ElFormItem label="允许新用户注册">
                <ElSwitch v-model="featureForm.allow_register" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">关闭后新用户无法创建账号</span>
              </ElFormItem>
              <!-- <ElFormItem label="一键注册并登录">
                <ElSwitch
                  v-model="featureForm.allow_quick_register"
                  :disabled="
                    !featureForm.allow_register || featureForm.require_invite_code || isDemoAdmin
                  "
                />
                <span class="feature-setting-help"
                  >创建正式账号并直接登录，邀请码必填时自动停用</span
                >
              </ElFormItem> -->
              <ElFormItem label="单设备每日上限">
                <ElInputNumber
                  v-model="featureForm.quick_register_device_limit"
                  :min="1"
                  :max="20"
                  :disabled="!featureForm.allow_register || isDemoAdmin"
                />
                <span class="feature-setting-help">限制同一设备每天快捷注册次数</span>
              </ElFormItem>
              <ElFormItem label="单 IP 每日上限">
                <ElInputNumber
                  v-model="featureForm.quick_register_ip_limit"
                  :min="1"
                  :max="1000"
                  :disabled="!featureForm.allow_register || isDemoAdmin"
                />
                <span class="feature-setting-help">限制同一网络出口每天快捷注册次数</span>
              </ElFormItem>
              <ElFormItem label="必须填写邀请码">
                <ElSwitch v-model="featureForm.require_invite_code" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">开启后仅持有有效邀请码的用户可以注册</span>
              </ElFormItem>
              <ElFormItem label="必须选择性别">
                <ElSwitch
                  v-model="featureForm.require_gender_on_register"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">关闭后可稍后在个人资料中补充</span>
              </ElFormItem>
              <ElFormItem label="强制绑定手机号">
                <ElSwitch v-model="featureForm.require_phone_bind" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">
                  未绑定手机号前不可使用消息、通讯录和钱包等核心功能
                </span>
              </ElFormItem>
              <ElFormItem label="邀请码位数">
                <ElInputNumber
                  v-model="featureForm.user_invite_code_length"
                  :min="6"
                  :max="10"
                  :step="1"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">
                  新生成的个人邀请码位数（6-10）。历史 10 位邀请码始终兼容可继续使用
                </span>
              </ElFormItem>
              <ElFormItem label="注册用户名类型" class="feature-setting-grid__wide">
                <ElRadioGroup v-model="featureForm.username_type" :disabled="isDemoAdmin">
                  <ElRadioButton value="phone">仅中国手机号</ElRadioButton>
                  <ElRadioButton value="alphanumeric">英文和数字</ElRadioButton>
                </ElRadioGroup>
                <span class="feature-setting-help">
                  选择「仅中国手机号」时，注册用户名必须是有效中国大陆手机号；
                  选择「英文和数字」时，用户名只允许英文字母与数字，长度 3-20 位
                </span>
              </ElFormItem>
              <ElFormItem label="加好友方式" class="feature-setting-grid__wide">
                <ElRadioGroup v-model="featureForm.friend_add_mode" :disabled="isDemoAdmin">
                  <ElRadioButton value="direct">无需验证</ElRadioButton>
                  <ElRadioButton value="approval">需要验证</ElRadioButton>
                  <ElRadioButton value="disabled">禁止添加</ElRadioButton>
                </ElRadioGroup>
                <span class="feature-setting-help">
                  直接建立双方联系人、发送申请等待同意，或禁止普通用户建立新的好友关系
                </span>
              </ElFormItem>
            </div>
          </section>

          <section class="feature-section-card">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"><ArtSvgIcon icon="ri:apple-line" /></span>
              <div>
                <span class="feature-section-header__eyebrow">App 合规</span>
                <h3>App 合规模式</h3>
                <p>对所有移动端用户统一生效，不按审核账号、设备或审核人员做差异化处理。</p>
              </div>
              <ElSwitch v-model="featureForm.ios_compliance.enabled" :disabled="isDemoAdmin" />
            </header>
            <div
              class="feature-setting-grid"
              :class="{ 'feature-setting-grid--muted': !featureForm.ios_compliance.enabled }"
            >
              <ElFormItem label="保留 VIP 入口">
                <ElSwitch
                  v-model="featureForm.ios_compliance.vip_enabled"
                  :disabled="!featureForm.ios_compliance.enabled || isDemoAdmin"
                />
                <span class="feature-setting-help">没有接入 Apple 内购时建议关闭</span>
              </ElFormItem>
              <ElFormItem label="保留钱包入口">
                <ElSwitch
                  v-model="featureForm.ios_compliance.wallet_enabled"
                  :disabled="!featureForm.ios_compliance.enabled || isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="允许钱包充值">
                <ElSwitch
                  v-model="featureForm.ios_compliance.wallet_recharge_enabled"
                  :disabled="
                    !featureForm.ios_compliance.enabled ||
                    !featureForm.ios_compliance.wallet_enabled ||
                    isDemoAdmin
                  "
                />
                <span class="feature-setting-help">关闭后 iOS 不展示微信、支付宝等充值入口</span>
              </ElFormItem>
              <ElFormItem label="允许广场视频">
                <ElSwitch
                  v-model="featureForm.ios_compliance.moment_video_enabled"
                  :disabled="!featureForm.ios_compliance.enabled || isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="保留自定义栏目">
                <ElSwitch
                  v-model="featureForm.ios_compliance.custom_portal_enabled"
                  :disabled="!featureForm.ios_compliance.enabled || isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="保留签到入口">
                <ElSwitch
                  v-model="featureForm.ios_compliance.checkin_enabled"
                  :disabled="!featureForm.ios_compliance.enabled || isDemoAdmin"
                />
              </ElFormItem>
            </div>
          </section>

          <section class="feature-section-card feature-section-card--moment">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"
                ><ArtSvgIcon icon="ri:compass-3-line"
              /></span>
              <div>
                <span class="feature-section-header__eyebrow">内容社区</span>
                <h3>广场功能</h3>
                <p>控制用户是否可以发布动态，以及新动态是否需要后台审核。</p>
              </div>
            </header>
            <div class="feature-setting-grid">
              <ElFormItem label="允许发布动态">
                <ElSwitch v-model="featureForm.enable_moment_post" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">关闭后用户仍可浏览，但不能发布动态</span>
              </ElFormItem>
              <ElFormItem label="动态发布审核">
                <ElSwitch
                  v-model="featureForm.moment_post_review_enabled"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">新动态审核通过后才会在广场展示</span>
              </ElFormItem>
            </div>
          </section>

          <section class="feature-section-card feature-section-card--portal">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"
                ><ArtSvgIcon icon="ri:layout-grid-line"
              /></span>
              <div>
                <span class="feature-section-header__eyebrow">导航扩展</span>
                <h3>客户端自定义栏目</h3>
                <p>在“联系人”和“发现”之间增加一个由后台配置名称、图标和网址的入口。</p>
              </div>
              <ElSwitch v-model="featureForm.custom_portal_enabled" :disabled="isDemoAdmin" />
            </header>
            <div
              class="feature-setting-grid"
              :class="{ 'feature-setting-grid--muted': !featureForm.custom_portal_enabled }"
            >
              <ElFormItem label="栏目名称">
                <ElInput
                  v-model="featureForm.custom_portal_title"
                  maxlength="20"
                  show-word-limit
                  placeholder="例如：官网"
                  :disabled="!featureForm.custom_portal_enabled || isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="栏目图标">
                <div class="feature-portal-upload">
                  <ElUpload
                    :action="portalUploadUrl"
                    :headers="portalUploadHeaders"
                    :show-file-list="false"
                    accept="image/*"
                    :disabled="!featureForm.custom_portal_enabled || isDemoAdmin"
                    :on-success="handlePortalIconUploadSuccess"
                  >
                    <div class="feature-portal-upload__preview">
                      <img
                        v-if="featureForm.custom_portal_icon_url"
                        :src="fixImageUrl(featureForm.custom_portal_icon_url)"
                        alt="portal-icon"
                      />
                      <ArtSvgIcon v-else icon="ri:image-add-line" />
                    </div>
                  </ElUpload>
                  <span>建议上传 64 × 64 的正方形图片</span>
                </div>
              </ElFormItem>
              <ElFormItem label="打开网址" class="feature-setting-grid__wide">
                <ElInput
                  v-model="featureForm.custom_portal_url"
                  placeholder="例如：https://example.com"
                  :disabled="!featureForm.custom_portal_enabled || isDemoAdmin"
                />
                <span class="feature-setting-help">
                  若目标网站限制内嵌显示，客户端会提供在浏览器中直接打开的入口
                </span>
              </ElFormItem>
            </div>
          </section>

          <section class="feature-section-card feature-section-card--new-user">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"
                ><ArtSvgIcon icon="ri:user-add-line"
              /></span>
              <div>
                <span class="feature-section-header__eyebrow">用户初始化</span>
                <h3>新用户默认关系</h3>
                <p>设置新账号注册完成后自动建立的官方用户、群组和频道关系。</p>
              </div>
            </header>
            <div class="feature-setting-grid">
              <ElFormItem label="关注官方用户">
                <ElSwitch v-model="featureForm.new_user_follow_official" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">注册后自动关注后台配置的官方用户</span>
              </ElFormItem>
              <!-- <ElFormItem label="邀请码只加绑定客服">
                <ElSwitch v-model="featureForm.invite_register_bind_only" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">邀请码用户仅自动添加其绑定客服</span>
              </ElFormItem> -->
              <ElFormItem label="加入官方群组">
                <ElSwitch v-model="featureForm.new_user_join_group" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">注册后自动加入指定官方群组</span>
              </ElFormItem>
              <ElFormItem label="订阅官方频道">
                <ElSwitch v-model="featureForm.new_user_join_channel" :disabled="isDemoAdmin" />
                <span class="feature-setting-help">注册后自动订阅指定官方频道</span>
              </ElFormItem>
            </div>
          </section>

          <section class="feature-section-card feature-section-card--group">
            <header class="feature-section-header">
              <span class="feature-section-header__icon"
                ><ArtSvgIcon icon="ri:group-2-line"
              /></span>
              <div>
                <span class="feature-section-header__eyebrow">会话规则</span>
                <h3>群组、频道与消息策略</h3>
                <p>统一配置成员容量、消息频控、撤回时限以及客户端消息加密模式。</p>
              </div>
            </header>
            <div class="feature-setting-grid">
              <ElFormItem label="非好友不可拉群">
                <ElSwitch
                  v-model="featureForm.group_invite_require_friend"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">用户只能邀请自己的联系人加入群聊</span>
              </ElFormItem>
              <ElFormItem label="群组成员上限">
                <ElInputNumber
                  v-model="featureForm.group_max_members"
                  :min="100"
                  :max="1000000"
                  :step="10000"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">默认 200000 人</span>
              </ElFormItem>
              <ElFormItem label="频道订阅者上限">
                <ElInputNumber
                  v-model="featureForm.channel_max_members"
                  :min="0"
                  :max="10000000"
                  :step="100000"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">设置为 0 表示不限制</span>
              </ElFormItem>
              <ElFormItem label="消息撤回时限">
                <ElInputNumber
                  v-model="featureForm.revoke_message_minutes"
                  :min="1"
                  :max="60"
                  :step="1"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">单位：分钟，默认 2 分钟</span>
              </ElFormItem>
              <ElFormItem label="IP 消息频率">
                <ElInputNumber
                  v-model="featureForm.ip_rate_limit"
                  :min="0"
                  :max="10000"
                  :step="10"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">同一 IP 每分钟消息数，0 表示不限制</span>
              </ElFormItem>
              <ElFormItem label="用户消息频率">
                <ElInputNumber
                  v-model="featureForm.user_rate_limit"
                  :min="0"
                  :max="10000"
                  :step="10"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <span class="feature-setting-help">单个用户每分钟消息数，0 表示不限制</span>
              </ElFormItem>
              <ElFormItem label="消息加密模式" class="feature-setting-grid__wide">
                <ElRadioGroup v-model="featureForm.message_crypto_mode" :disabled="isDemoAdmin">
                  <ElRadio value="plain">明文模式</ElRadio>
                  <ElRadio value="compatible">兼容加密</ElRadio>
                  <ElRadio value="strict">严格加密</ElRadio>
                </ElRadioGroup>
                <span class="feature-setting-help feature-setting-help--block">
                  明文模式便于后台查询；兼容加密会在端到端加密失败时回退明文；严格加密仅允许发送端到端加密消息。
                </span>
              </ElFormItem>
            </div>
          </section>
          <template v-if="false">
            <ElDivider content-position="left">语音转文字</ElDivider>
            <ElFormItem label="识别服务">
              <ElRadioGroup v-model="featureForm.voice_transcribe_provider" :disabled="isDemoAdmin">
                <ElRadio value="">关闭</ElRadio>
                <ElRadio value="openai">OpenAI</ElRadio>
                <ElRadio value="custom">自定义接口</ElRadio>
              </ElRadioGroup>
            </ElFormItem>
            <template v-if="featureForm.voice_transcribe_provider === 'openai'">
              <ElFormItem label="OpenAI API Key">
                <ElInput
                  v-model="featureForm.openai_api_key"
                  type="password"
                  :show-password="!isDemoAdmin"
                  placeholder="sk-..."
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="识别模型">
                <ElInput
                  v-model="featureForm.openai_transcribe_model"
                  placeholder="gpt-4o-mini-transcribe"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="接口地址">
                <ElInput
                  v-model="featureForm.openai_transcribe_url"
                  placeholder="https://api.openai.com/v1/audio/transcriptions"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
            </template>
            <template v-if="featureForm.voice_transcribe_provider === 'custom'">
              <ElFormItem label="自定义接口">
                <ElInput
                  v-model="featureForm.voice_transcribe_url"
                  placeholder="https://example.com/transcribe"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="Bearer Token">
                <ElInput
                  v-model="featureForm.voice_transcribe_token"
                  type="password"
                  :show-password="!isDemoAdmin"
                  placeholder="可选"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
            </template>
            <ElFormItem label="语言">
              <ElInput
                v-model="featureForm.voice_transcribe_language"
                placeholder="可选，例如 zh / en"
                :disabled="featureForm.voice_transcribe_provider === '' || isDemoAdmin"
              />
            </ElFormItem>
            <ElDivider content-position="left">DeepSeek 翻译</ElDivider>
            <ElAlert type="info" :closable="false" show-icon class="mb-4">
              用于客户端消息“翻译”功能。语音转文字仍使用上方 OpenAI 或自定义语音识别接口。
            </ElAlert>
            <ElFormItem label="DeepSeek API Key">
              <ElInput
                v-model="featureForm.deepseek_api_key"
                type="password"
                :show-password="!isDemoAdmin"
                :placeholder="isDemoAdmin ? '******' : 'sk-...'"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="接口 Base URL">
              <ElInput
                v-model="featureForm.deepseek_base_url"
                placeholder="https://api.deepseek.com"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="模型">
              <ElInput
                v-model="featureForm.deepseek_model"
                placeholder="deepseek-v4-flash"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElDivider content-position="left">心跳检测</ElDivider>
            <ElFormItem label="心跳超时时间">
              <ElInputNumber
                v-model="featureForm.heartbeat_timeout"
                :min="10"
                :max="600"
                :step="10"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <span class="ml-2 text-sm text-g-400"
                >秒，超过此时间未收到心跳则视为离线（默认60秒，修改后需重启后端）</span
              >
            </ElFormItem>
            <ElDivider content-position="left">云存储</ElDivider>
            <ElFormItem label="存储方式">
              <ElRadioGroup v-model="cloudStorageForm.provider" :disabled="isDemoAdmin">
                <ElRadio value="local">本地</ElRadio>
                <ElRadio value="aliyun">阿里云 OSS</ElRadio>
                <ElRadio value="qiniu">七牛云</ElRadio>
                <ElRadio value="s3">Amazon S3</ElRadio>
              </ElRadioGroup>
            </ElFormItem>
            <template v-if="cloudStorageForm.provider === 'local'">
              <ElFormItem label="本地访问域名">
                <ElInput
                  v-model="cloudStorageForm.local.base_url"
                  placeholder="留空使用后端 server.base_url"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
            </template>
            <template v-if="cloudStorageForm.provider === 'aliyun'">
              <ElFormItem label="OSS Endpoint">
                <ElInput
                  v-model="cloudStorageForm.aliyun.endpoint"
                  placeholder="例如 oss-cn-hangzhou.aliyuncs.com"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="OSS Bucket">
                <ElInput
                  v-model="cloudStorageForm.aliyun.bucket"
                  placeholder="Bucket 名称"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="AccessKey ID">
                <ElInput
                  v-model="cloudStorageForm.aliyun.access_key_id"
                  :placeholder="isDemoAdmin ? '******' : '阿里云 AccessKey ID'"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="AccessKey Secret">
                <ElInput
                  v-model="cloudStorageForm.aliyun.access_key_secret"
                  type="password"
                  :show-password="!isDemoAdmin"
                  :placeholder="isDemoAdmin ? '******' : '阿里云 AccessKey Secret'"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="访问域名">
                <ElInput
                  v-model="cloudStorageForm.aliyun.public_base_url"
                  placeholder="例如 https://cdn.example.com，留空使用 Bucket Endpoint"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="HTTPS">
                <ElSwitch v-model="cloudStorageForm.aliyun.use_https" :disabled="isDemoAdmin" />
              </ElFormItem>
            </template>
            <template v-if="cloudStorageForm.provider === 'qiniu'">
              <ElFormItem label="上传接口地址">
                <ElInput
                  v-model="cloudStorageForm.qiniu.upload_url"
                  placeholder="默认 https://upload.qiniup.com"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="Bucket">
                <ElInput
                  v-model="cloudStorageForm.qiniu.bucket"
                  placeholder="Bucket 名称"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="AccessKey">
                <ElInput
                  v-model="cloudStorageForm.qiniu.access_key"
                  :placeholder="isDemoAdmin ? '******' : '七牛云 AccessKey'"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="SecretKey">
                <ElInput
                  v-model="cloudStorageForm.qiniu.secret_key"
                  type="password"
                  :show-password="!isDemoAdmin"
                  :placeholder="isDemoAdmin ? '******' : '七牛云 SecretKey'"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="访问域名">
                <ElInput
                  v-model="cloudStorageForm.qiniu.public_base_url"
                  placeholder="例如 https://cdn.example.com"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="HTTPS">
                <ElSwitch v-model="cloudStorageForm.qiniu.use_https" :disabled="isDemoAdmin" />
              </ElFormItem>
            </template>
            <template v-if="cloudStorageForm.provider === 's3'">
              <ElAlert
                class="mb-4"
                type="success"
                :closable="false"
                title="AWS 密钥将加密保存到后台数据库，页面仅显示掩码，客户端无法获取。"
              />
              <ElFormItem label="Access Key ID">
                <ElInput
                  v-model="cloudStorageForm.s3.access_key_id"
                  placeholder="请输入 AWS Access Key ID"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="Secret Access Key">
                <ElInput
                  v-model="cloudStorageForm.s3.secret_access_key"
                  type="password"
                  show-password
                  autocomplete="new-password"
                  placeholder="请输入 AWS Secret Access Key"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="AWS Region">
                <ElInput
                  v-model="cloudStorageForm.s3.region"
                  placeholder="例如 ap-southeast-1"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="S3 Bucket">
                <ElInput
                  v-model="cloudStorageForm.s3.bucket"
                  placeholder="Bucket 名称"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="媒体访问域名">
                <ElInput
                  v-model="cloudStorageForm.s3.public_base_url"
                  placeholder="例如 https://media.example.com"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="自定义 Endpoint">
                <ElInput
                  v-model="cloudStorageForm.s3.endpoint"
                  placeholder="Amazon S3 留空"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="Path Style">
                <ElSwitch
                  v-model="cloudStorageForm.s3.use_path_style"
                  :disabled="isDemoAdmin || !cloudStorageForm.s3.endpoint"
                />
              </ElFormItem>
            </template>
            <ElDivider content-position="left">文件上传限制</ElDivider>
            <ElFormItem label="图片大小限制">
              <ElInputNumber
                v-model="featureForm.max_image_size"
                :min="1"
                :max="100"
                :step="1"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <span class="ml-2 text-sm text-g-400">MB，默认10MB</span>
            </ElFormItem>
            <ElFormItem label="视频大小限制">
              <ElInputNumber
                v-model="featureForm.max_video_size"
                :min="10"
                :max="1000"
                :step="10"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <span class="ml-2 text-sm text-g-400">MB，默认100MB</span>
            </ElFormItem>
            <ElFormItem label="文件大小限制">
              <ElInputNumber
                v-model="featureForm.max_file_size"
                :min="10"
                :max="1000"
                :step="10"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <span class="ml-2 text-sm text-g-400">MB，默认100MB</span>
            </ElFormItem>
            <ElFormItem label="语音大小限制">
              <ElInputNumber
                v-model="featureForm.max_voice_size"
                :min="1"
                :max="100"
                :step="1"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <span class="ml-2 text-sm text-g-400">MB，默认20MB</span>
            </ElFormItem>
          </template>
          <div v-if="!isDemoAdmin" class="feature-save-bar">
            <div>
              <strong>保存客户端功能配置</strong>
              <span>修改保存后，新配置将在客户端下次同步系统设置时生效。</span>
            </div>
            <ElButton type="primary" size="large" :loading="saving" @click="saveFeatureSettings">
              <ArtSvgIcon icon="ri:save-3-line" />
              保存客户端功能
            </ElButton>
          </div>
        </ElForm>
      </ElTabPane>

      <!-- AI配置 -->
      <ElTabPane label="AI配置" name="ai">
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          您当前是演示管理员，只能查看设置，无法进行修改。敏感配置已隐藏。
        </ElAlert>
        <ElForm :model="featureForm" label-width="180px" class="max-w-2xl">
          <ElDivider content-position="left">语音转文字</ElDivider>
          <ElFormItem label="识别服务">
            <ElRadioGroup v-model="featureForm.voice_transcribe_provider" :disabled="isDemoAdmin">
              <ElRadio value="">关闭</ElRadio>
              <ElRadio value="openai">OpenAI</ElRadio>
              <ElRadio value="custom">自定义接口</ElRadio>
            </ElRadioGroup>
          </ElFormItem>
          <template v-if="featureForm.voice_transcribe_provider === 'openai'">
            <ElFormItem label="OpenAI API Key">
              <ElInput
                v-model="featureForm.openai_api_key"
                type="password"
                :show-password="!isDemoAdmin"
                placeholder="sk-..."
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="识别模型">
              <ElInput
                v-model="featureForm.openai_transcribe_model"
                placeholder="gpt-4o-mini-transcribe"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="接口地址">
              <ElInput
                v-model="featureForm.openai_transcribe_url"
                placeholder="https://api.openai.com/v1/audio/transcriptions"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
          </template>
          <template v-if="featureForm.voice_transcribe_provider === 'custom'">
            <ElFormItem label="自定义接口">
              <ElInput
                v-model="featureForm.voice_transcribe_url"
                placeholder="https://example.com/transcribe"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="Bearer Token">
              <ElInput
                v-model="featureForm.voice_transcribe_token"
                type="password"
                :show-password="!isDemoAdmin"
                placeholder="可选"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
          </template>
          <ElFormItem label="语言">
            <ElInput
              v-model="featureForm.voice_transcribe_language"
              placeholder="可选，例如 zh / en"
              :disabled="featureForm.voice_transcribe_provider === '' || isDemoAdmin"
            />
          </ElFormItem>
          <ElDivider content-position="left">DeepSeek 翻译</ElDivider>
          <ElAlert type="info" :closable="false" show-icon class="mb-4">
            用于客户端消息“翻译”功能。语音转文字仍使用上方 OpenAI 或自定义语音识别接口。
          </ElAlert>
          <ElFormItem label="DeepSeek API Key">
            <ElInput
              v-model="featureForm.deepseek_api_key"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : 'sk-...'"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="接口 Base URL">
            <ElInput
              v-model="featureForm.deepseek_base_url"
              placeholder="https://api.deepseek.com"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="模型">
            <ElInput
              v-model="featureForm.deepseek_model"
              placeholder="deepseek-v4-flash"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingAI" @click="saveAISettings">
              保存AI配置
            </ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- 存储配置 -->
      <ElTabPane label="存储配置" name="storage">
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          您当前是演示管理员，只能查看设置，无法进行修改。敏感配置已隐藏。
        </ElAlert>
        <ElForm :model="featureForm" label-width="180px" class="max-w-2xl">
          <ElDivider content-position="left">云存储</ElDivider>
          <div class="storage-diagnostics">
            <div class="storage-diagnostics-head">
              <div>
                <span class="storage-kicker">运行状态</span>
                <strong>{{ storageStatusTitle }}</strong>
              </div>
              <div class="storage-diagnostics-actions">
                <ElButton
                  size="small"
                  :loading="loadingStorageStatus"
                  @click="refreshStorageStatus"
                >
                  刷新状态
                </ElButton>
                <ElButton
                  v-if="!isDemoAdmin"
                  size="small"
                  type="primary"
                  :loading="testingStorage"
                  @click="handleStorageTestUpload"
                >
                  测试上传
                </ElButton>
              </div>
            </div>
            <div class="storage-diagnostics-grid">
              <div>
                <span>配置来源</span>
                <b>{{ storageSourceLabel(storageStatus?.source) }}</b>
              </div>
              <div>
                <span>公开域名</span>
                <b>{{ storageStatus?.public_base_url || '-' }}</b>
              </div>
              <div>
                <span>Endpoint</span>
                <b>{{ storageStatus?.endpoint || '-' }}</b>
              </div>
              <div>
                <span>Bucket</span>
                <b>{{ storageStatus?.bucket || '-' }}</b>
              </div>
            </div>
            <ElAlert
              v-if="storageStatus?.error"
              class="mt-3"
              type="warning"
              :closable="false"
              show-icon
            >
              {{ storageStatus.error }}
            </ElAlert>
            <div v-if="storageTestResult" class="storage-test-result">
              <div>
                <span>测试结果</span>
                <ElTag :type="storageTestResult.ok ? 'success' : 'danger'" effect="light">
                  {{ storageTestResult.ok ? '通过' : '失败' }}
                </ElTag>
              </div>
              <div>
                <span>HTTP</span>
                <b>{{ storageTestResult.http_status || '-' }}</b>
              </div>
              <div>
                <span>耗时</span>
                <b>{{ storageTestResult.duration_ms }}ms</b>
              </div>
              <ElLink
                v-if="storageTestResult.url && !storageTestResult.cleaned"
                type="primary"
                :href="storageTestResult.url"
                target="_blank"
              >
                打开文件
              </ElLink>
              <ElTag v-else-if="storageTestResult.cleaned" type="success" effect="plain">
                测试对象已清理
              </ElTag>
            </div>
            <div v-if="storageStatus?.upload_stages?.stages?.length" class="upload-stage-metrics">
              <div class="upload-stage-metrics__title">
                <strong>上传阶段耗时</strong>
                <span>进程启动后累计，便于定位签名、S3 与数据库瓶颈</span>
              </div>
              <ElTable :data="storageStatus.upload_stages.stages" size="small">
                <ElTableColumn prop="stage" label="阶段" min-width="150" />
                <ElTableColumn prop="count" label="次数" width="72" />
                <ElTableColumn prop="failed" label="失败" width="72" />
                <ElTableColumn label="平均" width="92">
                  <template #default="{ row }">{{ Number(row.average_ms).toFixed(1) }}ms</template>
                </ElTableColumn>
                <ElTableColumn label="最大" width="92">
                  <template #default="{ row }">{{ Number(row.max_ms).toFixed(1) }}ms</template>
                </ElTableColumn>
              </ElTable>
            </div>
          </div>
          <ElFormItem label="存储方式">
            <ElRadioGroup v-model="cloudStorageForm.provider" :disabled="isDemoAdmin">
              <ElRadio value="local">本地</ElRadio>
              <ElRadio value="aliyun">阿里云 OSS</ElRadio>
              <ElRadio value="qiniu">七牛云</ElRadio>
              <ElRadio value="s3">Amazon S3</ElRadio>
            </ElRadioGroup>
          </ElFormItem>
          <template v-if="cloudStorageForm.provider === 'local'">
            <ElFormItem label="本地访问域名">
              <ElInput
                v-model="cloudStorageForm.local.base_url"
                placeholder="留空使用后端 server.base_url"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
          </template>
          <template v-if="cloudStorageForm.provider === 'aliyun'">
            <ElFormItem label="OSS Endpoint">
              <ElInput
                v-model="cloudStorageForm.aliyun.endpoint"
                placeholder="例如 oss-cn-hangzhou.aliyuncs.com"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="OSS Bucket">
              <ElInput
                v-model="cloudStorageForm.aliyun.bucket"
                placeholder="Bucket 名称"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="AccessKey ID">
              <ElInput
                v-model="cloudStorageForm.aliyun.access_key_id"
                :placeholder="isDemoAdmin ? '******' : '阿里云 AccessKey ID'"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="AccessKey Secret">
              <ElInput
                v-model="cloudStorageForm.aliyun.access_key_secret"
                type="password"
                :show-password="!isDemoAdmin"
                :placeholder="isDemoAdmin ? '******' : '阿里云 AccessKey Secret'"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="访问域名">
              <ElInput
                v-model="cloudStorageForm.aliyun.public_base_url"
                placeholder="例如 https://cdn.example.com，留空使用 Bucket Endpoint"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="HTTPS">
              <ElSwitch v-model="cloudStorageForm.aliyun.use_https" :disabled="isDemoAdmin" />
            </ElFormItem>
          </template>
          <template v-if="cloudStorageForm.provider === 'qiniu'">
            <ElFormItem label="上传接口地址">
              <ElInput
                v-model="cloudStorageForm.qiniu.upload_url"
                placeholder="默认 https://upload.qiniup.com"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="Bucket">
              <ElInput
                v-model="cloudStorageForm.qiniu.bucket"
                placeholder="Bucket 名称"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="AccessKey">
              <ElInput
                v-model="cloudStorageForm.qiniu.access_key"
                :placeholder="isDemoAdmin ? '******' : '七牛云 AccessKey'"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="SecretKey">
              <ElInput
                v-model="cloudStorageForm.qiniu.secret_key"
                type="password"
                :show-password="!isDemoAdmin"
                :placeholder="isDemoAdmin ? '******' : '七牛云 SecretKey'"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="访问域名">
              <ElInput
                v-model="cloudStorageForm.qiniu.public_base_url"
                placeholder="例如 https://cdn.example.com"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="HTTPS">
              <ElSwitch v-model="cloudStorageForm.qiniu.use_https" :disabled="isDemoAdmin" />
            </ElFormItem>
          </template>
          <template v-if="cloudStorageForm.provider === 's3'">
            <ElAlert
              class="mb-4"
              type="success"
              :closable="false"
              title="AWS 密钥将加密保存到后台数据库，页面仅显示掩码，客户端无法获取。"
            />
            <ElFormItem label="Access Key ID">
              <ElInput
                v-model="cloudStorageForm.s3.access_key_id"
                placeholder="请输入 AWS Access Key ID"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="Secret Access Key">
              <ElInput
                v-model="cloudStorageForm.s3.secret_access_key"
                type="password"
                show-password
                autocomplete="new-password"
                placeholder="请输入 AWS Secret Access Key"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="AWS Region">
              <ElInput
                v-model="cloudStorageForm.s3.region"
                placeholder="例如 ap-southeast-1"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="S3 Bucket">
              <ElInput
                v-model="cloudStorageForm.s3.bucket"
                placeholder="Bucket 名称"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="媒体访问域名">
              <ElInput
                v-model="cloudStorageForm.s3.public_base_url"
                placeholder="例如 https://media.example.com"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="自定义 Endpoint">
              <ElInput
                v-model="cloudStorageForm.s3.endpoint"
                placeholder="Amazon S3 留空"
                :disabled="isDemoAdmin"
              />
            </ElFormItem>
            <ElFormItem label="Path Style">
              <ElSwitch
                v-model="cloudStorageForm.s3.use_path_style"
                :disabled="isDemoAdmin || !cloudStorageForm.s3.endpoint"
              />
            </ElFormItem>
          </template>
          <ElDivider content-position="left">聊天图片直传</ElDivider>
          <ElFormItem label="允许图片直传">
            <ElSwitch
              v-model="featureForm.chat_image_direct_upload_enabled"
              :disabled="isDemoAdmin || cloudStorageForm.provider !== 's3'"
            />
            <span v-if="cloudStorageForm.provider !== 's3'" class="ml-2 text-sm text-g-400">
              仅 Amazon S3 可启用
            </span>
          </ElFormItem>
          <ElFormItem label="启用平台">
            <ElCheckboxGroup
              v-model="featureForm.chat_image_direct_upload_platforms"
              :disabled="isDemoAdmin"
            >
              <ElCheckbox label="android">Android</ElCheckbox>
              <ElCheckbox label="ios">iOS</ElCheckbox>
              <ElCheckbox label="windows">Windows</ElCheckbox>
              <ElCheckbox label="macos">macOS</ElCheckbox>
              <ElCheckbox label="linux">Linux</ElCheckbox>
              <ElCheckbox label="web">Web</ElCheckbox>
            </ElCheckboxGroup>
          </ElFormItem>
          <ElFormItem label="灰度比例">
            <ElInputNumber
              v-model="featureForm.chat_image_direct_upload_rollout_percent"
              :min="0"
              :max="100"
              :step="5"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">%（按用户稳定分桶）</span>
          </ElFormItem>
          <ElFormItem label="客户端并发上限">
            <ElInputNumber
              v-model="featureForm.chat_image_direct_upload_max_concurrency"
              :min="1"
              :max="3"
              :step="1"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">建议 2–3</span>
          </ElFormItem>
          <ElDivider content-position="left">文件上传限制</ElDivider>
          <ElFormItem label="图片大小限制">
            <ElInputNumber
              v-model="featureForm.max_image_size"
              :min="1"
              :max="100"
              :step="1"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">MB，默认10MB</span>
          </ElFormItem>
          <ElFormItem label="视频大小限制">
            <ElInputNumber
              v-model="featureForm.max_video_size"
              :min="10"
              :max="1000"
              :step="10"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">MB，默认100MB</span>
          </ElFormItem>
          <ElFormItem label="文件大小限制">
            <ElInputNumber
              v-model="featureForm.max_file_size"
              :min="10"
              :max="1000"
              :step="10"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">MB，默认100MB</span>
          </ElFormItem>
          <ElFormItem label="语音大小限制">
            <ElInputNumber
              v-model="featureForm.max_voice_size"
              :min="1"
              :max="100"
              :step="1"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">MB，默认20MB</span>
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingStorage" @click="saveStorageSettings">
              保存存储配置
            </ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <ElTabPane v-if="false" label="入口容灾" name="client-bootstrap">
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          演示管理员只能查看客户端入口容灾配置。
        </ElAlert>
        <ElAlert v-else type="info" :closable="false" show-icon class="mb-4">
          这里配置 App 可用的 API、WebSocket 和资源入口。保存后 App 下次刷新 bootstrap
          会自动拿到新入口，不需要重新打包。
        </ElAlert>

        <div class="failover-page">
          <div class="failover-hero">
            <div>
              <p class="failover-eyebrow">客户端访问入口</p>
              <h3>主入口不可用时，App 自动切到备用入口</h3>
              <p>
                这里只需要维护线上可访问的域名。主入口优先使用，备用入口按顺序接管；
                连接策略保持默认即可，只有网络环境特殊时再打开高级设置。
              </p>
            </div>
            <div class="failover-status">
              <ElTag :type="clientBootstrapForm.enabled ? 'success' : 'info'" effect="light">
                {{ clientBootstrapForm.enabled ? '已启用' : '未启用' }}
              </ElTag>
              <span>版本 {{ clientBootstrapForm.version || 1 }}</span>
              <span>{{ clientBootstrapForm.api_endpoints.length }} 个访问入口</span>
            </div>
          </div>

          <ElForm :model="clientBootstrapForm" label-position="top" class="failover-form">
            <section class="failover-section">
              <div class="section-title">
                <div>
                  <h4>基础设置</h4>
                  <p>日常只需要开关、版本和缓存时间。</p>
                </div>
              </div>
              <div class="basic-setting-grid">
                <ElFormItem label="启用动态入口">
                  <ElSwitch v-model="clientBootstrapForm.enabled" :disabled="isDemoAdmin" />
                </ElFormItem>
                <ElFormItem label="配置版本">
                  <ElInputNumber
                    v-model="clientBootstrapForm.version"
                    :min="1"
                    :step="1"
                    controls-position="right"
                    :disabled="isDemoAdmin"
                  />
                  <p class="form-tip">每次调整入口后加 1，客户端会更快识别新配置。</p>
                </ElFormItem>
                <ElFormItem label="客户端缓存">
                  <ElSelect v-model="clientBootstrapForm.ttl_seconds" :disabled="isDemoAdmin">
                    <ElOption label="5 分钟" :value="300" />
                    <ElOption label="15 分钟" :value="900" />
                    <ElOption label="30 分钟" :value="1800" />
                    <ElOption label="1 小时" :value="3600" />
                  </ElSelect>
                </ElFormItem>
              </div>
            </section>

            <section class="failover-section">
              <div class="section-title">
                <div>
                  <h4>访问入口</h4>
                  <p>一组入口包含 API 和 WebSocket。通常主域名一组，备用域名一组。</p>
                </div>
                <ElButton v-if="!isDemoAdmin" @click="addFailoverEndpoint">
                  <ArtSvgIcon icon="ri:add-line" class="mr-1" />
                  添加备用入口
                </ElButton>
              </div>

              <div class="endpoint-cards">
                <div
                  v-for="(item, index) in clientBootstrapForm.api_endpoints"
                  :key="`endpoint-card-${index}`"
                  class="endpoint-card"
                >
                  <div class="endpoint-card-head">
                    <div>
                      <ElTag :type="index === 0 ? 'success' : 'info'" effect="light">
                        {{ index === 0 ? '主入口' : `备用入口 ${index}` }}
                      </ElTag>
                      <span class="endpoint-name">{{ item.id || `entry-${index + 1}` }}</span>
                    </div>
                    <ElButton
                      v-if="!isDemoAdmin && clientBootstrapForm.api_endpoints.length > 1"
                      type="danger"
                      link
                      @click="removeFailoverEndpoint(index)"
                    >
                      删除
                    </ElButton>
                  </div>

                  <div class="endpoint-card-grid">
                    <ElFormItem label="API 地址">
                      <ElInput
                        v-model="item.url"
                        placeholder="https://api.example.com"
                        :disabled="isDemoAdmin"
                        @blur="fillWsFromApi(index)"
                      />
                    </ElFormItem>
                    <ElFormItem label="WebSocket 地址">
                      <ElInput
                        v-if="clientBootstrapForm.ws_endpoints[index]"
                        v-model="clientBootstrapForm.ws_endpoints[index].url"
                        placeholder="wss://api.example.com/api/v1/ws"
                        :disabled="isDemoAdmin"
                      />
                    </ElFormItem>
                    <ElFormItem label="备注">
                      <ElInput
                        v-model="item.region"
                        placeholder="例如：主线路 / 香港备用 / 高防备用"
                        :disabled="isDemoAdmin"
                      />
                    </ElFormItem>
                  </div>
                </div>
              </div>
            </section>

            <section class="failover-section">
              <div class="section-title">
                <div>
                  <h4>资源入口</h4>
                  <p>头像、图片、语音、文件会优先使用这里的域名。没有 CDN 时填 API 域名即可。</p>
                </div>
                <ElButton v-if="!isDemoAdmin" @click="addMediaBaseUrl">
                  <ArtSvgIcon icon="ri:add-line" class="mr-1" />
                  添加资源域名
                </ElButton>
              </div>
              <div class="media-url-list">
                <div
                  v-for="(_item, index) in clientBootstrapForm.media_base_urls"
                  :key="`simple-media-${index}`"
                  class="media-url-row"
                >
                  <ElInput
                    v-model="clientBootstrapForm.media_base_urls[index]"
                    placeholder="https://cdn.example.com"
                    :disabled="isDemoAdmin"
                  />
                  <ElButton
                    v-if="!isDemoAdmin && clientBootstrapForm.media_base_urls.length > 1"
                    type="danger"
                    link
                    @click="removeMediaBaseUrl(index)"
                  >
                    删除
                  </ElButton>
                </div>
              </div>
            </section>

            <section class="failover-section">
              <ElCollapse>
                <ElCollapseItem title="高级切换策略" name="advanced">
                  <div class="strategy-presets">
                    <ElButton :disabled="isDemoAdmin" @click="applyClientStrategyPreset('stable')">
                      稳定优先
                    </ElButton>
                    <ElButton :disabled="isDemoAdmin" @click="applyClientStrategyPreset('fast')">
                      快速切换
                    </ElButton>
                  </div>
                  <div class="strategy-grid">
                    <ElFormItem label="连接超时">
                      <ElInputNumber
                        v-model="clientBootstrapForm.strategy.connect_timeout_ms"
                        :min="1000"
                        :max="30000"
                        :step="500"
                        controls-position="right"
                        :disabled="isDemoAdmin"
                      />
                      <p class="form-tip">毫秒</p>
                    </ElFormItem>
                    <ElFormItem label="失败切换阈值">
                      <ElInputNumber
                        v-model="clientBootstrapForm.strategy.fail_threshold"
                        :min="1"
                        :max="10"
                        :step="1"
                        controls-position="right"
                        :disabled="isDemoAdmin"
                      />
                    </ElFormItem>
                    <ElFormItem label="失败冷却">
                      <ElInputNumber
                        v-model="clientBootstrapForm.strategy.cooldown_seconds"
                        :min="10"
                        :max="3600"
                        :step="10"
                        controls-position="right"
                        :disabled="isDemoAdmin"
                      />
                      <p class="form-tip">秒</p>
                    </ElFormItem>
                    <ElFormItem label="优先使用上次成功入口">
                      <ElSwitch
                        v-model="clientBootstrapForm.strategy.prefer_last_success"
                        :disabled="isDemoAdmin"
                      />
                    </ElFormItem>
                  </div>
                </ElCollapseItem>
              </ElCollapse>
            </section>

            <div v-if="!isDemoAdmin" class="failover-actions">
              <ElButton
                type="primary"
                size="large"
                :loading="savingClientBootstrap"
                @click="saveClientBootstrap"
              >
                保存入口配置
              </ElButton>
            </div>
          </ElForm>
        </div>

        <div v-if="false" class="client-bootstrap-guide">
          <div>
            <p class="guide-title">给客户看的使用说明</p>
            <p class="guide-desc">
              这个页面不是“服务器集群开关”，而是给客户端下发一份可用入口名单。主域名访问异常时， App
              会按优先级自动尝试备用
              API、备用消息连接和备用资源域名，减少客户因为单个域名不可用导致的中断。
            </p>
          </div>
          <div class="guide-grid">
            <div class="guide-item">
              <span class="guide-index">1</span>
              <div>
                <strong>API 入口</strong>
                <p>填写 App 调接口用的域名，例如登录、聊天列表、联系人等接口域名。</p>
                <code>https://api-a.example.com</code>
              </div>
            </div>
            <div class="guide-item">
              <span class="guide-index">2</span>
              <div>
                <strong>WebSocket 入口</strong>
                <p>填写实时消息长连接地址，通常和 API 使用同一域名，只是协议为 wss。</p>
                <code>wss://api-a.example.com/api/v1/ws</code>
              </div>
            </div>
            <div class="guide-item">
              <span class="guide-index">3</span>
              <div>
                <strong>资源/CDN 入口</strong>
                <p>填写头像、图片、文件等资源访问域名。没有独立 CDN 时可先填 API 域名。</p>
                <code>https://cdn-a.example.com</code>
              </div>
            </div>
          </div>
          <ElAlert type="success" :closable="false" show-icon class="mt-3">
            建议配置 2-3 组不同域名：主入口优先级填 10，备用入口填 20、30。数字越小越优先。
            每次调整入口后把“配置版本”加 1，客户端会更快识别到新配置。
          </ElAlert>
        </div>

        <ElForm v-if="false" :model="clientBootstrapForm" label-width="160px" class="max-w-5xl">
          <ElFormItem label="启用动态入口">
            <ElSwitch v-model="clientBootstrapForm.enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">关闭后仍会保留服务端默认兜底入口</span>
          </ElFormItem>
          <ElFormItem label="配置版本">
            <ElInputNumber
              v-model="clientBootstrapForm.version"
              :min="1"
              :step="1"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">每次调整入口建议递增</span>
          </ElFormItem>
          <ElFormItem label="客户端缓存时间">
            <ElInputNumber
              v-model="clientBootstrapForm.ttl_seconds"
              :min="30"
              :max="86400"
              :step="60"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">秒，建议 300-1800</span>
          </ElFormItem>

          <ElDivider content-position="left">API 入口</ElDivider>
          <p class="endpoint-help">
            客户端访问业务接口的地址。比如登录、同步聊天列表、发送消息接口都会走这里。
            健康检查路径一般保持 <code>/api/v1/ping</code>。
          </p>
          <div class="endpoint-list">
            <div class="endpoint-row endpoint-row--api endpoint-row-head">
              <span>入口名称</span>
              <span>API 地址</span>
              <span>优先级</span>
              <span>区域备注</span>
              <span>健康检查</span>
              <span>操作</span>
            </div>
            <div
              v-for="(item, index) in clientBootstrapForm.api_endpoints"
              :key="`api-${index}`"
              class="endpoint-row endpoint-row--api"
            >
              <ElInput v-model="item.id" placeholder="如：main-api" :disabled="isDemoAdmin" />
              <ElInput
                v-model="item.url"
                placeholder="如：https://api-a.example.com"
                :disabled="isDemoAdmin"
                class="endpoint-url"
              />
              <ElInputNumber
                v-model="item.priority"
                :min="1"
                :step="10"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <ElInput
                v-model="item.region"
                placeholder="如：主线路/香港/备用"
                :disabled="isDemoAdmin"
              />
              <ElInput
                v-model="item.health_path"
                placeholder="/api/v1/ping"
                :disabled="isDemoAdmin"
              />
              <ElButton
                v-if="!isDemoAdmin"
                type="danger"
                link
                @click="removeClientEndpoint('api', index)"
              >
                删除
              </ElButton>
            </div>
            <ElButton v-if="!isDemoAdmin" @click="addClientEndpoint('api')">
              <ArtSvgIcon icon="ri:add-line" class="mr-1" />
              添加 API 入口
            </ElButton>
          </div>

          <ElDivider content-position="left">WebSocket 入口</ElDivider>
          <p class="endpoint-help">
            客户端实时收消息、在线状态、消息回执使用这个地址。生产环境建议使用
            <code>wss://</code>，路径一般是 <code>/api/v1/ws</code>。
          </p>
          <div class="endpoint-list">
            <div class="endpoint-row endpoint-row--ws endpoint-row-head">
              <span>入口名称</span>
              <span>WS 地址</span>
              <span>优先级</span>
              <span>区域备注</span>
              <span>操作</span>
            </div>
            <div
              v-for="(item, index) in clientBootstrapForm.ws_endpoints"
              :key="`ws-${index}`"
              class="endpoint-row endpoint-row--ws"
            >
              <ElInput v-model="item.id" placeholder="如：main-ws" :disabled="isDemoAdmin" />
              <ElInput
                v-model="item.url"
                placeholder="如：wss://api-a.example.com/api/v1/ws"
                :disabled="isDemoAdmin"
                class="endpoint-url"
              />
              <ElInputNumber
                v-model="item.priority"
                :min="1"
                :step="10"
                controls-position="right"
                :disabled="isDemoAdmin"
              />
              <ElInput
                v-model="item.region"
                placeholder="如：主线路/香港/备用"
                :disabled="isDemoAdmin"
              />
              <ElButton
                v-if="!isDemoAdmin"
                type="danger"
                link
                @click="removeClientEndpoint('ws', index)"
              >
                删除
              </ElButton>
            </div>
            <ElButton v-if="!isDemoAdmin" @click="addClientEndpoint('ws')">
              <ArtSvgIcon icon="ri:add-line" class="mr-1" />
              添加 WS 入口
            </ElButton>
          </div>

          <ElDivider content-position="left">资源/CDN 入口</ElDivider>
          <p class="endpoint-help">
            客户端加载头像、图片、文件、语音等资源会使用这里。没有单独 CDN 时，可以先填写当前 API
            域名。
          </p>
          <div class="endpoint-list">
            <div class="media-row media-row-head">
              <span>资源访问地址</span>
              <span>操作</span>
            </div>
            <div
              v-for="(_item, index) in clientBootstrapForm.media_base_urls"
              :key="`media-${index}`"
              class="media-row"
            >
              <ElInput
                v-model="clientBootstrapForm.media_base_urls[index]"
                placeholder="如：https://cdn-a.example.com"
                :disabled="isDemoAdmin"
              />
              <ElButton v-if="!isDemoAdmin" type="danger" link @click="removeMediaBaseUrl(index)">
                删除
              </ElButton>
            </div>
            <ElButton v-if="!isDemoAdmin" @click="addMediaBaseUrl">
              <ArtSvgIcon icon="ri:add-line" class="mr-1" />
              添加资源入口
            </ElButton>
          </div>

          <ElDivider content-position="left">切换策略</ElDivider>
          <p class="endpoint-help">
            默认策略已经适合大多数客户。只有网络环境很差，或者备用入口切换太慢时，再调整这里。
          </p>
          <ElFormItem label="连接超时">
            <ElInputNumber
              v-model="clientBootstrapForm.strategy.connect_timeout_ms"
              :min="1000"
              :max="30000"
              :step="500"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">毫秒</span>
          </ElFormItem>
          <ElFormItem label="健康检查超时">
            <ElInputNumber
              v-model="clientBootstrapForm.strategy.health_timeout_ms"
              :min="1000"
              :max="30000"
              :step="500"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">毫秒</span>
          </ElFormItem>
          <ElFormItem label="失败切换阈值">
            <ElInputNumber
              v-model="clientBootstrapForm.strategy.fail_threshold"
              :min="1"
              :max="10"
              :step="1"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">连续失败多少次后切换入口</span>
          </ElFormItem>
          <ElFormItem label="失败冷却时间">
            <ElInputNumber
              v-model="clientBootstrapForm.strategy.cooldown_seconds"
              :min="10"
              :max="3600"
              :step="10"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">秒</span>
          </ElFormItem>
          <ElFormItem label="优先上次成功入口">
            <ElSwitch
              v-model="clientBootstrapForm.strategy.prefer_last_success"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingClientBootstrap" @click="saveClientBootstrap">
              保存入口容灾配置
            </ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- 官方群组 -->
      <ElTabPane label="官方群组" name="official-groups">
        <div class="mb-4">
          <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon>
            您当前是演示管理员，只能查看官方群组列表
          </ElAlert>
          <ElAlert v-else type="info" :closable="false" show-icon>
            官方群组会在App中显示官方标识，用户无法退出官方群组
          </ElAlert>
        </div>
        <div class="mb-4" v-if="!isDemoAdmin">
          <ElButton type="primary" @click="showAddOfficialGroup">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            添加官方群组
          </ElButton>
        </div>
        <ElTable :data="officialGroups" v-loading="loadingGroups" border stripe>
          <ElTableColumn type="index" width="60" label="#" />
          <ElTableColumn label="群组" min-width="200">
            <template #default="{ row }">
              <div class="flex items-center gap-2">
                <ElAvatar
                  :size="36"
                  :src="getAvatarUrl(row.avatar, row.chat_uuid)"
                  shape="square"
                />
                <div>
                  <p class="font-medium">{{ row.name }}</p>
                  <p class="text-xs text-g-400">{{ row.member_count }} 成员</p>
                </div>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="username" label="用户名" width="150">
            <template #default="{ row }">
              <span v-if="row.username">{{ row.username }}</span>
              <span v-else class="text-g-400">-</span>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="chat_uuid" label="UUID" width="300">
            <template #default="{ row }">
              <code class="text-xs">{{ row.chat_uuid }}</code>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="remark" label="备注" width="150" />
          <ElTableColumn v-if="!isDemoAdmin" label="操作" width="100" fixed="right">
            <template #default="{ row }">
              <ElButton type="danger" link size="small" @click="handleRemoveOfficialGroup(row)">
                移除
              </ElButton>
            </template>
          </ElTableColumn>
        </ElTable>
      </ElTabPane>

      <!-- 协议文档 -->
      <ElTabPane label="协议文档" name="agreements">
        <div class="mb-4">
          <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon>
            您当前是演示管理员，只能查看协议文档
          </ElAlert>
          <ElAlert v-else type="info" :closable="false" show-icon>
            用户协议和隐私政策支持 Markdown 格式，将在 App 登录页面和设置页面展示
          </ElAlert>
        </div>
        <ElForm label-width="120px" class="max-w-4xl">
          <ElFormItem label="用户协议">
            <ElInput
              v-model="agreementForm.user_agreement"
              type="textarea"
              :rows="15"
              placeholder="请输入用户协议内容（支持 Markdown 格式）"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingAgreement" @click="saveUserAgreement">
              保存用户协议
            </ElButton>
            <ElButton @click="previewAgreement('user')">预览</ElButton>
          </ElFormItem>
          <ElFormItem v-else>
            <ElButton @click="previewAgreement('user')">预览用户协议</ElButton>
          </ElFormItem>
          <ElDivider />
          <ElFormItem label="隐私政策">
            <ElInput
              v-model="agreementForm.privacy_policy"
              type="textarea"
              :rows="15"
              placeholder="请输入隐私政策内容（支持 Markdown 格式）"
              :disabled="isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingAgreement" @click="savePrivacyPolicy">
              保存隐私政策
            </ElButton>
            <ElButton @click="previewAgreement('privacy')">预览</ElButton>
          </ElFormItem>
          <ElFormItem v-else>
            <ElButton @click="previewAgreement('privacy')">预览隐私政策</ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- 官方频道 -->
      <ElTabPane label="官方频道" name="official-channels">
        <div class="mb-4">
          <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon>
            您当前是演示管理员，只能查看官方频道列表
          </ElAlert>
          <ElAlert v-else type="info" :closable="false" show-icon>
            官方频道会在App中显示官方标识，用户无法取消订阅官方频道
          </ElAlert>
        </div>
        <div class="mb-4" v-if="!isDemoAdmin">
          <ElButton type="primary" @click="showAddOfficialChannel">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            添加官方频道
          </ElButton>
        </div>
        <ElTable :data="officialChannels" v-loading="loadingChannels" border stripe>
          <ElTableColumn type="index" width="60" label="#" />
          <ElTableColumn label="频道" min-width="200">
            <template #default="{ row }">
              <div class="flex items-center gap-2">
                <ElAvatar
                  :size="36"
                  :src="getAvatarUrl(row.avatar, row.chat_uuid)"
                  shape="square"
                />
                <div>
                  <p class="font-medium">{{ row.name }}</p>
                  <p class="text-xs text-g-400">{{ row.member_count }} 订阅者</p>
                </div>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="username" label="用户名" width="150">
            <template #default="{ row }">
              <span v-if="row.username">{{ row.username }}</span>
              <span v-else class="text-g-400">-</span>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="chat_uuid" label="UUID" width="300">
            <template #default="{ row }">
              <code class="text-xs">{{ row.chat_uuid }}</code>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="remark" label="备注" width="150" />
          <ElTableColumn v-if="!isDemoAdmin" label="操作" width="100" fixed="right">
            <template #default="{ row }">
              <ElButton type="danger" link size="small" @click="handleRemoveOfficialChannel(row)">
                移除
              </ElButton>
            </template>
          </ElTableColumn>
        </ElTable>
      </ElTabPane>
    </ElTabs>

    <!-- 添加官方群组弹窗 -->
    <ElDialog v-model="addGroupDialogVisible" title="添加官方群组" width="500px">
      <ElForm :model="addGroupForm" label-width="80px">
        <ElFormItem label="群组" required>
          <ElInput v-model="addGroupForm.username" placeholder="输入群组 UUID 或用户名" />
        </ElFormItem>
        <ElFormItem label="备注">
          <ElInput v-model="addGroupForm.remark" placeholder="备注说明（可选）" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="addGroupDialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="addingGroup" @click="handleAddOfficialGroup">
          添加
        </ElButton>
      </template>
    </ElDialog>

    <!-- 添加官方频道弹窗 -->
    <ElDialog v-model="addChannelDialogVisible" title="添加官方频道" width="500px">
      <ElForm :model="addChannelForm" label-width="80px">
        <ElFormItem label="频道" required>
          <ElInput v-model="addChannelForm.username" placeholder="输入频道 UUID 或用户名" />
        </ElFormItem>
        <ElFormItem label="备注">
          <ElInput v-model="addChannelForm.remark" placeholder="备注说明（可选）" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="addChannelDialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="addingChannel" @click="handleAddOfficialChannel">
          添加
        </ElButton>
      </template>
    </ElDialog>

    <!-- 协议预览弹窗 -->
    <ElDialog v-model="previewDialogVisible" :title="previewTitle" width="800px" top="5vh">
      <div class="agreement-preview prose max-w-none" v-html="previewHtml"></div>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import {
    getSystemSettings,
    updateSystemSettings,
    getOfficialGroups,
    addOfficialGroup,
    addOfficialGroupByUsername,
    removeOfficialGroup,
    getOfficialChannels,
    addOfficialChannel,
    addOfficialChannelByUsername,
    removeOfficialChannel,
    getStorageStatus,
    testStorageUpload,
    OfficialGroup,
    OfficialChannel,
    type CloudStorageConfig,
    type ClientBootstrapConfig,
    type ClientEndpointConfig,
    type StorageStatusResponse,
    type StorageTestUploadResponse,
    type SystemSettings
  } from '@/api/admin'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import type { FormInstance, FormRules } from 'element-plus'
  import { fixImageUrl, getAvatarUrl } from '@/utils/url'
  import { useSettingStore } from '@/store/modules/setting'
  import { useUserStore } from '@/store/modules/user'
  import { useRoute } from 'vue-router'

  defineOptions({ name: 'SystemSettings' })

  const settingStore = useSettingStore()
  const userStore = useUserStore()
  const route = useRoute()

  // 是否是演示管理员（只能查看，不能编辑）
  const isDemoAdmin = ref(false)
  const adminRole = ref('')

  const routeTabMap: Record<string, string> = {
    SystemRTCSettings: 'rtc',
    SystemFeatureSettings: 'features',
    SystemAIConfig: 'ai',
    SystemStorageConfig: 'storage'
  }

  const getDefaultTabFromRoute = () => routeTabMap[String(route.name || '')] || 'basic'

  const activeTab = ref(getDefaultTabFromRoute())
  const saving = ref(false)
  const savingRTC = ref(false)
  const savingAI = ref(false)
  const savingStorage = ref(false)
  const loadingStorageStatus = ref(false)
  const testingStorage = ref(false)
  const storageStatus = ref<StorageStatusResponse | null>(null)
  const storageTestResult = ref<StorageTestUploadResponse | null>(null)
  const storageStatusTitle = computed(() => {
    if (!storageStatus.value) {
      return '未读取'
    }
    const providerMap: Record<string, string> = {
      local: '本地存储',
      aliyun: '阿里云 OSS',
      qiniu: '七牛云',
      s3: 'Amazon S3'
    }
    const label = providerMap[storageStatus.value.provider] || storageStatus.value.provider
    return storageStatus.value.valid === false ? `${label} 配置异常` : `${label} 正常`
  })

  const storageSourceLabel = (source?: string) => {
    const labels: Record<string, string> = {
      database: '数据库',
      env: '环境变量',
      yaml: '配置文件',
      default: '默认值'
    }
    return source ? labels[source] || source : '-'
  }

  // 基本信息
  const basicForm = reactive({
    system_name: '',
    system_version: '',
    register_base_url: '',
    support_online_url: '',
    support_qq: '',
    app_version_ios: '',
    app_version_android: '',
    app_force_update: false,
    app_update_url: '',
    app_update_url_ios: '',
    app_update_url_android: '',
    min_supported_version_ios: '',
    min_supported_version_android: '',
    app_update_message: '',
    splash_enabled: false,
    splash_image_url: '',
    splash_duration_ms: 3000
  })
  const savingBasic = ref(false)
  const basicFormRef = ref<FormInstance>()

  // 功能设置
  const featureForm = reactive({
    allow_register: true,
    allow_quick_register: true,
    quick_register_device_limit: 1,
    quick_register_ip_limit: 5,
    force_keep_alive_enabled: false,
    require_invite_code: false,
    require_gender_on_register: true,
    require_phone_bind: false,
    username_type: 'phone' as NonNullable<SystemSettings['username_type']>,
    user_invite_code_length: 6,
    enable_moment_post: true,
    moment_post_review_enabled: false,
    new_user_follow_official: false,
    invite_register_bind_only: false,
    new_user_join_group: false,
    new_user_join_channel: false,
    group_invite_require_friend: false,
    friend_add_mode: 'approval' as NonNullable<SystemSettings['friend_add_mode']>,
    ios_compliance: {
      enabled: true,
      vip_enabled: false,
      wallet_enabled: false,
      wallet_recharge_enabled: false,
      moment_video_enabled: false,
      custom_portal_enabled: false,
      checkin_enabled: false
    },
    custom_portal_enabled: false,
    custom_portal_title: '',
    custom_portal_url: '',
    custom_portal_icon_url: '',
    chat_attachment_menu: {
      enabled: true,
      album: true,
      camera: true,
      call: true,
      location: true,
      red_packet: true,
      transfer: true,
      favorite: true,
      file: true
    },
    burn_after_read_enabled: true,
    message_crypto_mode: 'plain' as NonNullable<SystemSettings['message_crypto_mode']>,
    group_max_members: 200000,
    channel_max_members: 0,
    revoke_message_minutes: 2,
    ip_rate_limit: 60,
    user_rate_limit: 30,
    voice_transcribe_provider: '',
    voice_transcribe_url: '',
    voice_transcribe_token: '',
    voice_transcribe_language: '',
    openai_api_key: '',
    openai_transcribe_model: 'gpt-4o-mini-transcribe',
    openai_transcribe_url: '',
    deepseek_api_key: '',
    deepseek_base_url: 'https://api.deepseek.com',
    deepseek_model: 'deepseek-v4-flash',
    chat_image_direct_upload_enabled: false,
    chat_image_direct_upload_platforms: ['android', 'ios'] as string[],
    chat_image_direct_upload_rollout_percent: 0,
    chat_image_direct_upload_max_concurrency: 3,
    heartbeat_timeout: 60,
    // RTC 配置
    rtc_provider: 'agora' as 'agora' | 'livekit',
    agora_enabled: false,
    agora_app_id: '',
    agora_app_certificate: '',
    agora_token_expire: 3600,
    livekit_enabled: false,
    livekit_server_url: '',
    livekit_api_key: '',
    livekit_api_secret: '',
    livekit_token_expire: 3600,
    // APNs 推送配置
    apns_enabled: false,
    apns_bundle_id: '',
    apns_key_id: '',
    apns_team_id: '',
    apns_auth_key: '',
    apns_environment: 'development',
    // Android 推送（多通道）
    fcm_enabled: false,
    fcm_project_id: '',
    fcm_service_account_json: '',
    hms_enabled: false,
    hms_app_id: '',
    hms_app_secret: '',
    xiaomi_push_enabled: false,
    xiaomi_package_name: '',
    xiaomi_app_secret: '',
    oppo_push_enabled: false,
    oppo_app_key: '',
    oppo_app_secret: '',
    // 文件上传限制
    max_image_size: 10,
    max_video_size: 100,
    max_file_size: 100,
    max_voice_size: 20
  })

  const attachmentMenuEnabledCount = computed(
    () =>
      [
        featureForm.chat_attachment_menu.album,
        featureForm.chat_attachment_menu.camera,
        featureForm.chat_attachment_menu.call,
        featureForm.chat_attachment_menu.location,
        featureForm.chat_attachment_menu.red_packet,
        featureForm.chat_attachment_menu.transfer,
        featureForm.chat_attachment_menu.favorite,
        featureForm.chat_attachment_menu.file,
        featureForm.burn_after_read_enabled
      ].filter(Boolean).length
  )

  const createDefaultCloudStorageConfig = (): CloudStorageConfig => ({
    provider: 'local',
    local: {
      base_url: ''
    },
    aliyun: {
      endpoint: '',
      bucket: '',
      access_key_id: '',
      access_key_secret: '',
      public_base_url: '',
      use_https: true
    },
    qiniu: {
      upload_url: 'https://upload.qiniup.com',
      bucket: '',
      access_key: '',
      secret_key: '',
      public_base_url: '',
      use_https: true
    },
    s3: {
      region: '',
      bucket: '',
      access_key_id: '',
      secret_access_key: '',
      public_base_url: '',
      endpoint: '',
      use_path_style: false
    }
  })

  const cloudStorageForm = reactive<CloudStorageConfig>(createDefaultCloudStorageConfig())

  const currentHttpOrigin = () =>
    typeof window === 'undefined' ? 'https://api.example.com' : window.location.origin

  const currentWsUrl = () => {
    const origin = currentHttpOrigin()
    return `${origin.replace(/^https:\/\//, 'wss://').replace(/^http:\/\//, 'ws://')}/api/v1/ws`
  }

  const createDefaultClientBootstrapConfig = (): ClientBootstrapConfig => ({
    enabled: true,
    version: 1,
    ttl_seconds: 300,
    api_endpoints: [
      {
        id: 'main-api',
        url: currentHttpOrigin(),
        priority: 10,
        region: 'main',
        health_path: '/api/v1/ping'
      }
    ],
    ws_endpoints: [
      {
        id: 'main-ws',
        url: currentWsUrl(),
        priority: 10,
        region: 'main'
      }
    ],
    media_base_urls: [currentHttpOrigin()],
    strategy: {
      connect_timeout_ms: 5000,
      health_timeout_ms: 3000,
      fail_threshold: 1,
      cooldown_seconds: 60,
      prefer_last_success: true
    }
  })

  const clientBootstrapForm = reactive<ClientBootstrapConfig>(createDefaultClientBootstrapConfig())
  const savingClientBootstrap = ref(false)
  const trimUrl = (value: string) => value.trim().replace(/\/+$/, '')

  const deriveWsUrlFromApi = (rawUrl: string) => {
    const url = trimUrl(rawUrl)
    if (!url) return ''
    const wsBase = url.replace(/^https:\/\//, 'wss://').replace(/^http:\/\//, 'ws://')
    return `${wsBase}/api/v1/ws`
  }

  const syncClientEndpointPairs = () => {
    if (clientBootstrapForm.api_endpoints.length === 0) {
      clientBootstrapForm.api_endpoints.push({
        id: 'main-api',
        url: '',
        priority: 10,
        region: '',
        health_path: '/api/v1/ping'
      })
    }
    while (clientBootstrapForm.ws_endpoints.length < clientBootstrapForm.api_endpoints.length) {
      const index = clientBootstrapForm.ws_endpoints.length
      const api = clientBootstrapForm.api_endpoints[index]
      clientBootstrapForm.ws_endpoints.push({
        id: index === 0 ? 'main-ws' : `backup-ws-${index}`,
        url: deriveWsUrlFromApi(api?.url || ''),
        priority: api?.priority || (index + 1) * 10,
        region: api?.region || '',
        health_path: ''
      })
    }
  }

  const fillWsFromApi = (index: number) => {
    syncClientEndpointPairs()
    const api = clientBootstrapForm.api_endpoints[index]
    const ws = clientBootstrapForm.ws_endpoints[index]
    if (!api || !ws || ws.url) return
    ws.url = deriveWsUrlFromApi(api.url)
  }

  const addFailoverEndpoint = () => {
    const index = clientBootstrapForm.api_endpoints.length
    const priority = (index + 1) * 10
    clientBootstrapForm.api_endpoints.push({
      id: `backup-api-${index}`,
      url: '',
      priority,
      region: '',
      health_path: '/api/v1/ping'
    })
    clientBootstrapForm.ws_endpoints.push({
      id: `backup-ws-${index}`,
      url: '',
      priority,
      region: '',
      health_path: ''
    })
  }

  const removeFailoverEndpoint = (index: number) => {
    if (clientBootstrapForm.api_endpoints.length <= 1) {
      ElMessage.warning('至少保留一个访问入口')
      return
    }
    clientBootstrapForm.api_endpoints.splice(index, 1)
    clientBootstrapForm.ws_endpoints.splice(index, 1)
  }

  const applyClientStrategyPreset = (preset: 'stable' | 'fast') => {
    if (preset === 'stable') {
      clientBootstrapForm.ttl_seconds = 1800
      clientBootstrapForm.strategy.connect_timeout_ms = 5000
      clientBootstrapForm.strategy.health_timeout_ms = 3000
      clientBootstrapForm.strategy.fail_threshold = 2
      clientBootstrapForm.strategy.cooldown_seconds = 120
      clientBootstrapForm.strategy.prefer_last_success = true
      return
    }
    clientBootstrapForm.ttl_seconds = 300
    clientBootstrapForm.strategy.connect_timeout_ms = 3000
    clientBootstrapForm.strategy.health_timeout_ms = 2000
    clientBootstrapForm.strategy.fail_threshold = 1
    clientBootstrapForm.strategy.cooldown_seconds = 30
    clientBootstrapForm.strategy.prefer_last_success = true
  }

  const portalUploadUrl = computed(
    () =>
      `${(import.meta.env.VITE_API_URL || '/api/v1').replace(/\/$/, '')}/admin/settings/discover-items/upload-icon`
  )

  const portalUploadHeaders = computed(() => ({
    Authorization: `Bearer ${userStore.accessToken}`
  }))

  const handlePortalIconUploadSuccess = (res: any) => {
    const url = res?.data?.url || res?.url || ''
    if (!url) {
      ElMessage.error('图标上传失败')
      return
    }
    featureForm.custom_portal_icon_url = url
    ElMessage.success('图标上传成功')
  }

  const handleSplashImageUploadSuccess = (res: any) => {
    const url = res?.data?.url || res?.url || ''
    if (!url) {
      ElMessage.error('启动页图片上传失败')
      return
    }
    basicForm.splash_image_url = url
    ElMessage.success('启动页图片上传成功')
  }

  // 官方群组
  const officialGroups = ref<OfficialGroup[]>([])
  const loadingGroups = ref(false)
  const addGroupDialogVisible = ref(false)
  const addingGroup = ref(false)
  const addGroupForm = reactive({ username: '', remark: '' })

  // 官方频道
  const officialChannels = ref<OfficialChannel[]>([])
  const loadingChannels = ref(false)
  const addChannelDialogVisible = ref(false)
  const addingChannel = ref(false)
  const addChannelForm = reactive({ username: '', remark: '' })

  // 协议文档
  const agreementForm = reactive({
    user_agreement: '',
    privacy_policy: ''
  })
  const savingAgreement = ref(false)
  const previewDialogVisible = ref(false)
  const previewTitle = ref('')
  const previewHtml = ref('')

  const validateSystemName = (_rule: unknown, value: string, callback: (error?: Error) => void) => {
    if ((value || '').trim().length > 50) {
      callback(new Error('系统名称最多 50 个字符'))
      return
    }
    callback()
  }

  const validateVersionValue = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    const version = (value || '').trim()
    if (!version) {
      callback()
      return
    }
    const versionPattern = /^\d+(\.\d+){0,3}([-.][0-9A-Za-z]+)*$/
    if (!versionPattern.test(version)) {
      callback(new Error('格式不正确，请使用如 1.0.0 或 1.0.0-beta.1'))
      return
    }
    callback()
  }

  const validateUpdateUrl = (_rule: unknown, value: string, callback: (error?: Error) => void) => {
    const url = (value || '').trim()
    if (!url) {
      if (basicForm.app_force_update) {
        callback(new Error('开启强制更新时必须填写更新下载链接'))
        return
      }
      callback()
      return
    }
    try {
      const parsedUrl = new URL(url)
      if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
        callback(new Error('下载链接必须以 http:// 或 https:// 开头'))
        return
      }
      callback()
    } catch {
      callback(new Error('请输入有效的下载链接'))
    }
  }

  const validateAppStoreUrl = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    const url = (value || '').trim()
    if (!url) {
      callback()
      return
    }
    try {
      const parsed = new URL(url)
      if (
        parsed.protocol !== 'https:' ||
        !['apps.apple.com', 'itunes.apple.com', 'appstore.com'].includes(parsed.hostname.toLowerCase())
      ) {
        callback(new Error('必须填写 Apple 官方 App Store HTTPS 链接'))
        return
      }
      callback()
    } catch {
      callback(new Error('请输入有效的 App Store 链接'))
    }
  }

  const validateRegisterBaseUrl = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    const url = (value || '').trim()
    if (!url) {
      callback()
      return
    }
    try {
      const parsedUrl = new URL(url)
      if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
        callback(new Error('H5 分享地址必须以 http:// 或 https:// 开头'))
        return
      }
      const firstHostLabel = parsedUrl.hostname.toLowerCase().split('.')[0]
      if (
        ['api', 'imapi'].includes(firstHostLabel) ||
        parsedUrl.pathname === '/api' ||
        parsedUrl.pathname.startsWith('/api/')
      ) {
        callback(new Error('这里必须填写 H5 地址，不能填写 API 接口地址'))
        return
      }
      callback()
    } catch {
      callback(new Error('请输入有效的 H5 分享地址'))
    }
  }

  const validateSupportOnlineUrl = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    const url = (value || '').trim()
    if (!url) {
      callback()
      return
    }
    try {
      const parsedUrl = new URL(url)
      if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
        callback(new Error('在线客服链接必须以 http:// 或 https:// 开头'))
        return
      }
      callback()
    } catch {
      callback(new Error('请输入有效的在线客服链接'))
    }
  }

  const validateSupportQQ = (_rule: unknown, value: string, callback: (error?: Error) => void) => {
    const qq = (value || '').trim()
    if (qq.length > 50) {
      callback(new Error('QQ 客服号不能超过 50 个字符'))
      return
    }
    if (/[\r\n]/.test(qq)) {
      callback(new Error('QQ 客服号不能包含换行'))
      return
    }
    callback()
  }

  const validateUpdateMessage = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    if ((value || '').length > 500) {
      callback(new Error('更新提示信息最多 500 个字符'))
      return
    }
    callback()
  }

  const basicFormRules: FormRules = {
    system_name: [{ validator: validateSystemName, trigger: ['blur', 'change'] }],
    system_version: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    register_base_url: [{ validator: validateRegisterBaseUrl, trigger: ['blur', 'change'] }],
    support_online_url: [{ validator: validateSupportOnlineUrl, trigger: ['blur', 'change'] }],
    support_qq: [{ validator: validateSupportQQ, trigger: ['blur', 'change'] }],
    app_version_ios: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    app_version_android: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    min_supported_version_ios: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    min_supported_version_android: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    app_update_url_ios: [{ validator: validateAppStoreUrl, trigger: ['blur', 'change'] }],
    app_update_url_android: [{ validator: validateUpdateUrl, trigger: ['blur', 'change'] }],
    app_update_url: [{ validator: validateUpdateUrl, trigger: ['blur', 'change'] }],
    app_update_message: [{ validator: validateUpdateMessage, trigger: ['blur', 'change'] }]
  }

  const getEffectiveVersionPayload = () => {
    const systemVersion = basicForm.system_version.trim()
    return {
      system_name: basicForm.system_name,
      system_version: systemVersion,
      register_base_url: basicForm.register_base_url.trim().replace(/\/+$/, ''),
      support_online_url: basicForm.support_online_url.trim(),
      support_qq: basicForm.support_qq.trim(),
      app_version_ios: basicForm.app_version_ios.trim() || systemVersion,
      app_version_android: basicForm.app_version_android.trim() || systemVersion,
      latest_version_ios: basicForm.app_version_ios.trim() || systemVersion,
      latest_version_android: basicForm.app_version_android.trim() || systemVersion,
      app_force_update: basicForm.app_force_update,
      // Keep the legacy field populated for older clients while new clients
      // use the platform-specific values below.
      app_update_url:
        basicForm.app_update_url.trim() || basicForm.app_update_url_android.trim(),
      app_update_url_ios: basicForm.app_update_url_ios.trim(),
      app_update_url_android: basicForm.app_update_url_android.trim(),
      min_supported_version_ios: basicForm.min_supported_version_ios.trim(),
      min_supported_version_android: basicForm.min_supported_version_android.trim(),
      app_update_message: basicForm.app_update_message.trim(),
      splash_enabled: basicForm.splash_enabled,
      splash_image_url: basicForm.splash_image_url.trim(),
      splash_duration_ms: basicForm.splash_duration_ms || 3000
    }
  }

  const syncSystemVersionToPlatforms = () => {
    const systemVersion = basicForm.system_version.trim()
    if (!systemVersion) {
      ElMessage.warning('请先填写系统版本')
      return
    }
    basicForm.app_version_ios = systemVersion
    basicForm.app_version_android = systemVersion
    ElMessage.success('已同步到 iOS / Android 版本号')
  }

  const applyCloudStorageConfig = (value: unknown) => {
    const config =
      value && typeof value === 'object'
        ? (value as Partial<CloudStorageConfig>)
        : createDefaultCloudStorageConfig()
    const defaults = createDefaultCloudStorageConfig()
    // 接口可能来自未支持新供应商的旧版本；未知 provider 回退本地配置，避免表单进入无对应面板的状态。
    cloudStorageForm.provider = ['aliyun', 'qiniu', 's3'].includes(config.provider || '')
      ? (config.provider as CloudStorageConfig['provider'])
      : 'local'
    Object.assign(cloudStorageForm.local, defaults.local, config.local || {})
    Object.assign(cloudStorageForm.aliyun, defaults.aliyun, config.aliyun || {})
    Object.assign(cloudStorageForm.qiniu, defaults.qiniu, config.qiniu || {})
    Object.assign(cloudStorageForm.s3, defaults.s3, config.s3 || {})
  }

  // 保存时始终提交完整供应商结构，切换 provider 不会丢失其他面板中尚未生效的输入值。
  const buildCloudStoragePayload = (): CloudStorageConfig => ({
    provider: cloudStorageForm.provider,
    local: {
      base_url: cloudStorageForm.local.base_url.trim().replace(/\/+$/, '')
    },
    aliyun: {
      endpoint: cloudStorageForm.aliyun.endpoint.trim().replace(/\/+$/, ''),
      bucket: cloudStorageForm.aliyun.bucket.trim(),
      access_key_id: cloudStorageForm.aliyun.access_key_id.trim(),
      access_key_secret: cloudStorageForm.aliyun.access_key_secret.trim(),
      public_base_url: cloudStorageForm.aliyun.public_base_url.trim().replace(/\/+$/, ''),
      use_https: cloudStorageForm.aliyun.use_https
    },
    qiniu: {
      upload_url:
        cloudStorageForm.qiniu.upload_url.trim().replace(/\/+$/, '') || 'https://upload.qiniup.com',
      bucket: cloudStorageForm.qiniu.bucket.trim(),
      access_key: cloudStorageForm.qiniu.access_key.trim(),
      secret_key: cloudStorageForm.qiniu.secret_key.trim(),
      public_base_url: cloudStorageForm.qiniu.public_base_url.trim().replace(/\/+$/, ''),
      use_https: cloudStorageForm.qiniu.use_https
    },
    s3: {
      region: cloudStorageForm.s3.region.trim(),
      bucket: cloudStorageForm.s3.bucket.trim(),
      access_key_id: cloudStorageForm.s3.access_key_id.trim(),
      secret_access_key: cloudStorageForm.s3.secret_access_key.trim(),
      public_base_url: cloudStorageForm.s3.public_base_url.trim().replace(/\/+$/, ''),
      endpoint: cloudStorageForm.s3.endpoint.trim().replace(/\/+$/, ''),
      use_path_style: cloudStorageForm.s3.use_path_style
    }
  })

  const isValidHttpUrl = (value: string, allowHostOnly = true) => {
    const text = value.trim()
    if (!text) return true
    try {
      const finalUrl = /^https?:\/\//i.test(text) || !allowHostOnly ? text : `https://${text}`
      const parsedUrl = new URL(finalUrl)
      return ['http:', 'https:'].includes(parsedUrl.protocol)
    } catch {
      return false
    }
  }

  const isValidRTCUrl = (value: string) => {
    const text = value.trim()
    if (!text) return true
    try {
      const parsedUrl = new URL(text)
      return ['ws:', 'wss:', 'http:', 'https:'].includes(parsedUrl.protocol)
    } catch {
      return false
    }
  }

  const applyClientBootstrapConfig = (value: unknown) => {
    const defaults = createDefaultClientBootstrapConfig()
    const config =
      value && typeof value === 'object' ? (value as Partial<ClientBootstrapConfig>) : defaults
    Object.assign(clientBootstrapForm, defaults, config)
    clientBootstrapForm.api_endpoints = [...(config.api_endpoints || defaults.api_endpoints)]
    clientBootstrapForm.ws_endpoints = [...(config.ws_endpoints || defaults.ws_endpoints)]
    clientBootstrapForm.media_base_urls = [...(config.media_base_urls || defaults.media_base_urls)]
    clientBootstrapForm.strategy = {
      ...defaults.strategy,
      ...(config.strategy || {})
    }
    syncClientEndpointPairs()
  }

  const addClientEndpoint = (type: 'api' | 'ws') => {
    const list =
      type === 'api' ? clientBootstrapForm.api_endpoints : clientBootstrapForm.ws_endpoints
    const index = list.length + 1
    list.push({
      id: `${type}-${index}`,
      url: '',
      priority: index * 10,
      region: '',
      health_path: type === 'api' ? '/api/v1/ping' : ''
    })
  }

  const removeClientEndpoint = (type: 'api' | 'ws', index: number) => {
    const list =
      type === 'api' ? clientBootstrapForm.api_endpoints : clientBootstrapForm.ws_endpoints
    if (list.length <= 1) {
      ElMessage.warning(type === 'api' ? '至少保留一个 API 入口' : '至少保留一个 WS 入口')
      return
    }
    list.splice(index, 1)
  }

  const addMediaBaseUrl = () => {
    clientBootstrapForm.media_base_urls.push('')
  }

  const removeMediaBaseUrl = (index: number) => {
    if (clientBootstrapForm.media_base_urls.length <= 1) {
      ElMessage.warning('至少保留一个资源入口')
      return
    }
    clientBootstrapForm.media_base_urls.splice(index, 1)
  }

  const cleanClientEndpoints = (items: ClientEndpointConfig[], type: 'api' | 'ws') =>
    items
      .map((item, index) => ({
        id: item.id.trim() || `${type}-${index + 1}`,
        url: trimUrl(item.url),
        priority: item.priority || (index + 1) * 10,
        region: (item.region || '').trim(),
        health_path: type === 'api' ? (item.health_path || '/api/v1/ping').trim() : ''
      }))
      .filter((item) => item.url)

  const buildClientBootstrapPayload = (): ClientBootstrapConfig => {
    syncClientEndpointPairs()
    return {
      enabled: clientBootstrapForm.enabled,
      version: clientBootstrapForm.version || 1,
      ttl_seconds: clientBootstrapForm.ttl_seconds || 300,
      api_endpoints: cleanClientEndpoints(clientBootstrapForm.api_endpoints, 'api'),
      ws_endpoints: cleanClientEndpoints(clientBootstrapForm.ws_endpoints, 'ws'),
      media_base_urls: clientBootstrapForm.media_base_urls
        .map(trimUrl)
        .filter((item, index, arr) => item && arr.indexOf(item) === index),
      strategy: {
        connect_timeout_ms: clientBootstrapForm.strategy.connect_timeout_ms || 5000,
        health_timeout_ms: clientBootstrapForm.strategy.health_timeout_ms || 3000,
        fail_threshold: clientBootstrapForm.strategy.fail_threshold || 1,
        cooldown_seconds: clientBootstrapForm.strategy.cooldown_seconds || 60,
        prefer_last_success: clientBootstrapForm.strategy.prefer_last_success
      }
    }
  }

  const validateClientBootstrapPayload = (payload: ClientBootstrapConfig): string | null => {
    if (payload.ttl_seconds < 30) return '客户端缓存时间不能小于 30 秒'
    if (payload.api_endpoints.length === 0) return '至少需要配置一个 API 入口'
    if (payload.ws_endpoints.length === 0) return '至少需要配置一个 WebSocket 入口'
    if (payload.media_base_urls.length === 0) return '至少需要配置一个资源入口'
    if (payload.api_endpoints.some((item) => !isValidHttpUrl(item.url, false))) {
      return 'API 入口必须是有效的 http:// 或 https:// 地址'
    }
    if (payload.ws_endpoints.some((item) => !isValidRTCUrl(item.url))) {
      return 'WebSocket 入口必须是有效的 ws:// 或 wss:// 地址'
    }
    if (payload.media_base_urls.some((item) => !isValidHttpUrl(item, false))) {
      return '资源入口必须是有效的 http:// 或 https:// 地址'
    }
    if (payload.strategy.fail_threshold < 1) return '失败切换阈值不能小于 1'
    if (payload.strategy.cooldown_seconds < 10) return '失败冷却时间不能小于 10 秒'
    return null
  }

  const validateCloudStoragePayload = (payload: CloudStorageConfig): string | null => {
    if (payload.provider === 'local') {
      if (payload.local.base_url && !isValidHttpUrl(payload.local.base_url)) {
        return '本地访问域名格式不正确'
      }
      return null
    }

    if (payload.provider === 'aliyun') {
      if (
        !payload.aliyun.endpoint ||
        !payload.aliyun.bucket ||
        !payload.aliyun.access_key_id ||
        !payload.aliyun.access_key_secret
      ) {
        return '阿里云 OSS 的 Endpoint、Bucket、AccessKey ID、AccessKey Secret 不能为空'
      }
      if (payload.aliyun.public_base_url && !isValidHttpUrl(payload.aliyun.public_base_url)) {
        return '阿里云访问域名格式不正确'
      }
      return null
    }

    if (payload.provider === 'qiniu') {
      if (
        !payload.qiniu.bucket ||
        !payload.qiniu.access_key ||
        !payload.qiniu.secret_key ||
        !payload.qiniu.public_base_url
      ) {
        return '七牛云的 Bucket、AccessKey、SecretKey、访问域名不能为空'
      }
      if (!isValidHttpUrl(payload.qiniu.upload_url)) {
        return '七牛上传接口地址格式不正确'
      }
      if (!isValidHttpUrl(payload.qiniu.public_base_url)) {
        return '七牛访问域名格式不正确'
      }
    }

    if (payload.provider === 's3') {
      if (
        !payload.s3.region ||
        !payload.s3.bucket ||
        !payload.s3.access_key_id ||
        !payload.s3.secret_access_key ||
        !payload.s3.public_base_url
      ) {
        return 'Amazon S3 的 Access Key ID、Secret Access Key、Region、Bucket、媒体访问域名不能为空'
      }
      if (!isValidHttpUrl(payload.s3.public_base_url)) {
        return 'Amazon S3 媒体访问域名格式不正确'
      }
      if (payload.s3.endpoint && !isValidHttpUrl(payload.s3.endpoint, false)) {
        return 'Amazon S3 自定义 Endpoint 必须是完整的 http/https 地址'
      }
    }

    return null
  }

  const refreshStorageStatus = async () => {
    loadingStorageStatus.value = true
    try {
      storageStatus.value = await getStorageStatus()
    } catch {
      ElMessage.error('读取存储运行状态失败')
    } finally {
      loadingStorageStatus.value = false
    }
  }

  const handleStorageTestUpload = async () => {
    testingStorage.value = true
    try {
      storageTestResult.value = await testStorageUpload()
      if (storageTestResult.value.ok) {
        ElMessage.success('测试上传通过')
      } else {
        ElMessage.error(storageTestResult.value.error || '测试上传失败')
      }
      await refreshStorageStatus()
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '测试上传失败')
    } finally {
      testingStorage.value = false
    }
  }

  // 加载设置
  const loadSettings = async () => {
    try {
      const settings = await getSystemSettings()
      // 检查是否是演示管理员
      adminRole.value = settings._admin_role || ''
      isDemoAdmin.value = adminRole.value === 'demo_admin'
      // 基本信息
      basicForm.system_name = settings.system_name || ''
      basicForm.system_version = settings.system_version || ''
      basicForm.register_base_url = settings.register_base_url || ''
      basicForm.support_online_url = settings.support_online_url || ''
      basicForm.support_qq = settings.support_qq || ''
      if (settings.system_name) {
        settingStore.setSystemName(settings.system_name)
      }
      // 版本设置
      basicForm.app_version_ios = settings.app_version_ios || ''
      basicForm.app_version_android = settings.app_version_android || ''
      basicForm.app_version_ios = settings.latest_version_ios || basicForm.app_version_ios
      basicForm.app_version_android = settings.latest_version_android || basicForm.app_version_android
      basicForm.app_force_update = settings.app_force_update || false
      basicForm.app_update_url = settings.app_update_url || ''
      basicForm.app_update_url_ios = settings.app_update_url_ios || settings.app_update_url || ''
      basicForm.app_update_url_android = settings.app_update_url_android || settings.app_update_url || ''
      basicForm.min_supported_version_ios = settings.min_supported_version_ios || ''
      basicForm.min_supported_version_android = settings.min_supported_version_android || ''
      basicForm.app_update_message = settings.app_update_message || ''
      basicForm.splash_enabled = settings.splash_enabled || false
      basicForm.splash_image_url = settings.splash_image_url || ''
      basicForm.splash_duration_ms = settings.splash_duration_ms ?? 3000
      // 功能设置
      featureForm.allow_register = settings.allow_register !== false
      featureForm.allow_quick_register = settings.allow_quick_register === true
      featureForm.quick_register_device_limit = settings.quick_register_device_limit || 1
      featureForm.quick_register_ip_limit = settings.quick_register_ip_limit || 5
      featureForm.force_keep_alive_enabled = settings.force_keep_alive_enabled === true
      featureForm.require_invite_code = settings.require_invite_code || false
      featureForm.require_gender_on_register = settings.require_gender_on_register !== false
      featureForm.require_phone_bind = settings.require_phone_bind || false
      // 新字段缺失或值异常时采用「phone」，兼顾旧配置兼容和默认安全边界。
      featureForm.username_type = ['phone', 'alphanumeric'].includes(
        settings.username_type || ''
      )
        ? settings.username_type!
        : 'phone'
      const rawInviteLength =
        typeof settings.user_invite_code_length === 'number' ? settings.user_invite_code_length : 6
      const clampedInviteLength = Math.min(10, Math.max(6, Math.round(rawInviteLength)))
      featureForm.user_invite_code_length = clampedInviteLength
      featureForm.enable_moment_post = settings.enable_moment_post !== false
      featureForm.moment_post_review_enabled = settings.moment_post_review_enabled || false
      featureForm.new_user_follow_official = settings.new_user_follow_official || false
      featureForm.invite_register_bind_only = settings.invite_register_bind_only || false
      featureForm.new_user_join_group = settings.new_user_join_group || false
      featureForm.new_user_join_channel = settings.new_user_join_channel || false
      featureForm.group_invite_require_friend = settings.group_invite_require_friend || false
      // 新字段缺失或值异常时采用“需要验证”，兼顾旧配置兼容和默认安全边界。
      featureForm.friend_add_mode = ['direct', 'approval', 'disabled'].includes(
        settings.friend_add_mode || ''
      )
        ? settings.friend_add_mode!
        : 'approval'
      const iosCompliance = settings.ios_compliance
      featureForm.ios_compliance.enabled = iosCompliance?.enabled !== false
      featureForm.ios_compliance.vip_enabled = iosCompliance?.vip_enabled === true
      featureForm.ios_compliance.wallet_enabled = iosCompliance?.wallet_enabled === true
      featureForm.ios_compliance.wallet_recharge_enabled =
        iosCompliance?.wallet_enabled === true && iosCompliance?.wallet_recharge_enabled === true
      featureForm.ios_compliance.moment_video_enabled = iosCompliance?.moment_video_enabled === true
      featureForm.ios_compliance.custom_portal_enabled =
        iosCompliance?.custom_portal_enabled === true
      featureForm.ios_compliance.checkin_enabled = iosCompliance?.checkin_enabled === true
      featureForm.custom_portal_enabled = settings.custom_portal_enabled || false
      featureForm.custom_portal_title = settings.custom_portal_title || ''
      featureForm.custom_portal_url = settings.custom_portal_url || ''
      featureForm.custom_portal_icon_url = settings.custom_portal_icon_url || ''
      const attachmentMenu = settings.chat_attachment_menu
      featureForm.chat_attachment_menu.enabled = attachmentMenu?.enabled !== false
      featureForm.chat_attachment_menu.album = attachmentMenu?.album !== false
      featureForm.chat_attachment_menu.camera = attachmentMenu?.camera !== false
      featureForm.chat_attachment_menu.call = attachmentMenu?.call !== false
      featureForm.chat_attachment_menu.location = attachmentMenu?.location !== false
      featureForm.chat_attachment_menu.red_packet = attachmentMenu?.red_packet !== false
      featureForm.chat_attachment_menu.transfer = attachmentMenu?.transfer !== false
      featureForm.chat_attachment_menu.favorite = attachmentMenu?.favorite !== false
      featureForm.chat_attachment_menu.file = attachmentMenu?.file !== false
      featureForm.burn_after_read_enabled = settings.burn_after_read_enabled !== false
      featureForm.message_crypto_mode = settings.message_crypto_mode || 'plain'
      featureForm.group_max_members = settings.group_max_members ?? 200000
      featureForm.channel_max_members = settings.channel_max_members ?? 0
      featureForm.revoke_message_minutes = settings.revoke_message_minutes ?? 2
      featureForm.ip_rate_limit = settings.ip_rate_limit ?? 60
      featureForm.user_rate_limit = settings.user_rate_limit ?? 30
      featureForm.voice_transcribe_provider = settings.voice_transcribe_provider || ''
      featureForm.voice_transcribe_url = settings.voice_transcribe_url || ''
      featureForm.voice_transcribe_token = settings.voice_transcribe_token || ''
      featureForm.voice_transcribe_language = settings.voice_transcribe_language || ''
      featureForm.openai_api_key = settings.openai_api_key || ''
      featureForm.openai_transcribe_model =
        settings.openai_transcribe_model || 'gpt-4o-mini-transcribe'
      featureForm.openai_transcribe_url = settings.openai_transcribe_url || ''
      featureForm.deepseek_api_key = settings.deepseek_api_key || ''
      featureForm.deepseek_base_url = settings.deepseek_base_url || 'https://api.deepseek.com'
      featureForm.deepseek_model = settings.deepseek_model || 'deepseek-v4-flash'
      // 直传配置由服务端全局设置回填；数组复制可避免表单操作直接修改响应对象。
      featureForm.chat_image_direct_upload_enabled =
        settings.chat_image_direct_upload_enabled === true
      featureForm.chat_image_direct_upload_platforms =
        settings.chat_image_direct_upload_platforms?.length
          ? [...settings.chat_image_direct_upload_platforms]
          : ['android', 'ios']
      featureForm.chat_image_direct_upload_rollout_percent =
        settings.chat_image_direct_upload_rollout_percent ?? 0
      featureForm.chat_image_direct_upload_max_concurrency =
        settings.chat_image_direct_upload_max_concurrency ?? 3
      featureForm.heartbeat_timeout = settings.heartbeat_timeout ?? 60
      // RTC 配置
      featureForm.rtc_provider = settings.rtc_provider === 'livekit' ? 'livekit' : 'agora'
      featureForm.agora_enabled = settings.agora_enabled || false
      featureForm.agora_app_id = settings.agora_app_id || ''
      featureForm.agora_app_certificate = settings.agora_app_certificate || ''
      featureForm.agora_token_expire = settings.agora_token_expire ?? 3600
      featureForm.livekit_enabled = settings.livekit_enabled || false
      featureForm.livekit_server_url = settings.livekit_server_url || ''
      featureForm.livekit_api_key = settings.livekit_api_key || ''
      featureForm.livekit_api_secret = settings.livekit_api_secret || ''
      featureForm.livekit_token_expire = settings.livekit_token_expire ?? 3600
      // APNs 推送配置
      featureForm.apns_enabled = settings.apns_enabled || false
      featureForm.apns_bundle_id = settings.apns_bundle_id || ''
      featureForm.apns_key_id = settings.apns_key_id || ''
      featureForm.apns_team_id = settings.apns_team_id || ''
      featureForm.apns_auth_key = settings.apns_auth_key || ''
      featureForm.apns_environment = settings.apns_environment || 'development'
      // Android 推送（多通道）
      featureForm.fcm_enabled = settings.fcm_enabled || false
      featureForm.fcm_project_id = settings.fcm_project_id || ''
      featureForm.fcm_service_account_json = settings.fcm_service_account_json || ''
      featureForm.hms_enabled = settings.hms_enabled || false
      featureForm.hms_app_id = settings.hms_app_id || ''
      featureForm.hms_app_secret = settings.hms_app_secret || ''
      featureForm.xiaomi_push_enabled = settings.xiaomi_push_enabled || false
      featureForm.xiaomi_package_name = settings.xiaomi_package_name || ''
      featureForm.xiaomi_app_secret = settings.xiaomi_app_secret || ''
      featureForm.oppo_push_enabled = settings.oppo_push_enabled || false
      featureForm.oppo_app_key = settings.oppo_app_key || ''
      featureForm.oppo_app_secret = settings.oppo_app_secret || ''
      // 文件上传限制
      featureForm.max_image_size = settings.max_image_size ?? 10
      featureForm.max_video_size = settings.max_video_size ?? 100
      featureForm.max_file_size = settings.max_file_size ?? 100
      featureForm.max_voice_size = settings.max_voice_size ?? 20
      applyCloudStorageConfig(settings.cloud_storage)
      await refreshStorageStatus()
      applyClientBootstrapConfig(settings.client_bootstrap)
      // 协议文档
      agreementForm.user_agreement = settings.user_agreement || ''
      agreementForm.privacy_policy = settings.privacy_policy || ''
    } catch (error) {
      console.error('加载设置失败:', error)
    }
  }

  // 保存基本信息
  const saveBasicSettings = async () => {
    const isValid = await basicFormRef.value?.validate().catch(() => false)
    if (!isValid) return

    savingBasic.value = true
    try {
      const payload = getEffectiveVersionPayload()
      basicForm.app_version_ios = payload.app_version_ios
      basicForm.app_version_android = payload.app_version_android
      await updateSystemSettings(payload)
      settingStore.setSystemName(basicForm.system_name)
      ElMessage.success('基本信息已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingBasic.value = false
    }
  }

  const rtcSettingKeys = new Set([
    'rtc_provider',
    'agora_enabled',
    'agora_app_id',
    'agora_app_certificate',
    'agora_token_expire',
    'livekit_enabled',
    'livekit_server_url',
    'livekit_api_key',
    'livekit_api_secret',
    'livekit_token_expire'
  ])

  const pushSettingKeys = new Set([
    'apns_enabled',
    'apns_bundle_id',
    'apns_key_id',
    'apns_team_id',
    'apns_auth_key',
    'apns_environment',
    'fcm_enabled',
    'fcm_project_id',
    'fcm_service_account_json',
    'hms_enabled',
    'hms_app_id',
    'hms_app_secret',
    'xiaomi_push_enabled',
    'xiaomi_package_name',
    'xiaomi_app_secret',
    'oppo_push_enabled',
    'oppo_app_key',
    'oppo_app_secret'
  ])

  const aiSettingKeys = new Set([
    'voice_transcribe_provider',
    'voice_transcribe_url',
    'voice_transcribe_token',
    'voice_transcribe_language',
    'openai_api_key',
    'openai_transcribe_model',
    'openai_transcribe_url',
    'deepseek_api_key',
    'deepseek_base_url',
    'deepseek_model'
  ])

  // 设置页按后端保存接口拆分 payload；列入此集合的字段只由“存储设置”按钮提交。
  const storageSettingKeys = new Set([
    'max_image_size',
    'max_video_size',
    'max_file_size',
    'max_voice_size',
    'chat_image_direct_upload_enabled',
    'chat_image_direct_upload_platforms',
    'chat_image_direct_upload_rollout_percent',
    'chat_image_direct_upload_max_concurrency'
  ])

  type FeatureSettingsPayload = Partial<SystemSettings>

  type StorageSettingsPayload = Partial<SystemSettings> & {
    cloud_storage: CloudStorageConfig
  }

  const buildFeaturePayload = (): FeatureSettingsPayload => {
    return {
      ...Object.fromEntries(
        Object.entries(featureForm).filter(
          ([key]) =>
            !rtcSettingKeys.has(key) &&
            !pushSettingKeys.has(key) &&
            !aiSettingKeys.has(key) &&
            !storageSettingKeys.has(key)
        )
      ),
      custom_portal_title: featureForm.custom_portal_title.trim(),
      custom_portal_url: featureForm.custom_portal_url.trim(),
      custom_portal_icon_url: featureForm.custom_portal_icon_url.trim(),
      ios_compliance: {
        ...featureForm.ios_compliance,
        wallet_recharge_enabled:
          featureForm.ios_compliance.wallet_enabled &&
          featureForm.ios_compliance.wallet_recharge_enabled
      },
      message_crypto_mode: featureForm.message_crypto_mode,
      // 始终序列化为整数，避免空值/字符串造成后端解析失败
      user_invite_code_length: Math.min(
        10,
        Math.max(6, Math.round(Number(featureForm.user_invite_code_length) || 6))
      )
    }
  }

  const buildAIPayload = (): Partial<SystemSettings> => ({
    voice_transcribe_provider: featureForm.voice_transcribe_provider.trim(),
    voice_transcribe_url: featureForm.voice_transcribe_url.trim(),
    voice_transcribe_token: featureForm.voice_transcribe_token.trim(),
    voice_transcribe_language: featureForm.voice_transcribe_language.trim(),
    openai_api_key: featureForm.openai_api_key.trim(),
    openai_transcribe_model: featureForm.openai_transcribe_model.trim(),
    openai_transcribe_url: featureForm.openai_transcribe_url.trim(),
    deepseek_api_key: featureForm.deepseek_api_key.trim(),
    deepseek_base_url: featureForm.deepseek_base_url.trim(),
    deepseek_model: featureForm.deepseek_model.trim()
  })

  // 直传开关、灰度和并发上限与云存储配置必须原子提交，避免客户端拿到不可执行的半套配置。
  const buildStoragePayload = (): StorageSettingsPayload => ({
    max_image_size: featureForm.max_image_size,
    max_video_size: featureForm.max_video_size,
    max_file_size: featureForm.max_file_size,
    max_voice_size: featureForm.max_voice_size,
    chat_image_direct_upload_enabled: featureForm.chat_image_direct_upload_enabled,
    chat_image_direct_upload_platforms: [
      ...featureForm.chat_image_direct_upload_platforms
    ],
    chat_image_direct_upload_rollout_percent:
      featureForm.chat_image_direct_upload_rollout_percent,
    chat_image_direct_upload_max_concurrency:
      featureForm.chat_image_direct_upload_max_concurrency,
    cloud_storage: buildCloudStoragePayload()
  })

  const buildRTCPayload = () => ({
    rtc_provider: featureForm.rtc_provider,
    agora_enabled: featureForm.agora_enabled,
    agora_app_id: featureForm.agora_app_id.trim(),
    agora_app_certificate: featureForm.agora_app_certificate.trim(),
    agora_token_expire: featureForm.agora_token_expire,
    livekit_enabled: featureForm.livekit_enabled,
    livekit_server_url: featureForm.livekit_server_url.trim(),
    livekit_api_key: featureForm.livekit_api_key.trim(),
    livekit_api_secret: featureForm.livekit_api_secret.trim(),
    livekit_token_expire: featureForm.livekit_token_expire
  })

  const validateRTCPayload = (payload: ReturnType<typeof buildRTCPayload>): string | null => {
    if (!['agora', 'livekit'].includes(payload.rtc_provider)) {
      return '默认音视频接口只能选择 Agora 或 LiveKit'
    }
    if (payload.agora_enabled && (!payload.agora_app_id || !payload.agora_app_certificate)) {
      return '启用 Agora 时，App ID 与 App Certificate 不能为空'
    }
    if (payload.livekit_enabled) {
      if (!payload.livekit_server_url || !payload.livekit_api_key || !payload.livekit_api_secret) {
        return '启用 LiveKit 时，Server URL / API Key / API Secret 不能为空'
      }
      if (!isValidRTCUrl(payload.livekit_server_url)) {
        return 'LiveKit Server URL 必须以 ws://、wss://、http:// 或 https:// 开头'
      }
    }
    if (payload.rtc_provider === 'agora' && !payload.agora_enabled) {
      return '默认音视频接口选择 Agora 时，请先启用 Agora'
    }
    if (payload.rtc_provider === 'livekit' && !payload.livekit_enabled) {
      return '默认音视频接口选择 LiveKit 时，请先启用 LiveKit'
    }

    return null
  }

  const validateFeaturePayload = (
    payload: ReturnType<typeof buildFeaturePayload>
  ): string | null => {
    if (payload.custom_portal_enabled) {
      if (!payload.custom_portal_title) {
        return '启用自定义栏目时，栏目名称不能为空'
      }
      if (!payload.custom_portal_url) {
        return '启用自定义栏目时，打开网址不能为空'
      }
      if (!payload.custom_portal_icon_url) {
        return '启用自定义栏目时，请上传栏目图标'
      }
      try {
        const finalUrl = /^https?:\/\//i.test(payload.custom_portal_url)
          ? payload.custom_portal_url
          : `https://${payload.custom_portal_url}`
        const parsedUrl = new URL(finalUrl)
        if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
          return '自定义栏目网址必须以 http:// 或 https:// 开头'
        }
      } catch {
        return '请输入有效的自定义栏目网址'
      }
    }
    const inviteLength = Number(payload.user_invite_code_length)
    if (!Number.isInteger(inviteLength) || inviteLength < 6 || inviteLength > 10) {
      return '邀请码位数需为 6-10 之间的整数'
    }
    if (payload.username_type && !['phone', 'alphanumeric'].includes(payload.username_type)) {
      return '注册用户名类型必须为「仅中国手机号」或「英文和数字」'
    }
    return null
  }

  const validateAIPayload = (payload: ReturnType<typeof buildAIPayload>): string | null => {
    if (payload.voice_transcribe_provider === 'openai') {
      if (!payload.openai_api_key || !payload.openai_transcribe_model) {
        return '启用 OpenAI 语音识别时，API Key 与识别模型不能为空'
      }
      if (payload.openai_transcribe_url && !isValidHttpUrl(payload.openai_transcribe_url, false)) {
        return 'OpenAI 识别接口地址必须是有效的 http:// 或 https:// 链接'
      }
    }
    if (payload.voice_transcribe_provider === 'custom') {
      if (!payload.voice_transcribe_url) {
        return '启用自定义语音识别时，自定义接口不能为空'
      }
      if (!isValidHttpUrl(payload.voice_transcribe_url, false)) {
        return '自定义语音识别接口必须是有效的 http:// 或 https:// 链接'
      }
    }
    if (payload.deepseek_base_url && !isValidHttpUrl(payload.deepseek_base_url, false)) {
      return 'DeepSeek Base URL 必须是有效的 http:// 或 https:// 链接'
    }

    return null
  }

  const validateStoragePayload = (
    payload: ReturnType<typeof buildStoragePayload>
  ): string | null => {
    const storageError = validateCloudStoragePayload(payload.cloud_storage)
    if (storageError) return storageError
    if (
      payload.chat_image_direct_upload_enabled &&
      payload.cloud_storage.provider !== 's3'
    ) {
      return '启用聊天图片直传前，请先选择并配置 Amazon S3'
    }
    if (!payload.chat_image_direct_upload_platforms?.length) {
      return '聊天图片直传至少选择一个客户端平台'
    }
    return null
  }

  // 保存功能设置
  const saveFeatureSettings = async () => {
    const payload = buildFeaturePayload()
    const validationError = validateFeaturePayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    saving.value = true
    try {
      await updateSystemSettings(payload)
      ElMessage.success('客户端功能已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      saving.value = false
    }
  }

  const saveAISettings = async () => {
    const payload = buildAIPayload()
    const validationError = validateAIPayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    savingAI.value = true
    try {
      await updateSystemSettings(payload)
      ElMessage.success('AI配置已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingAI.value = false
    }
  }

  const saveStorageSettings = async () => {
    const payload = buildStoragePayload()
    const validationError = validateStoragePayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    savingStorage.value = true
    try {
      await updateSystemSettings(payload)
      await refreshStorageStatus()
      ElMessage.success('存储配置已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingStorage.value = false
    }
  }

  const saveClientBootstrap = async () => {
    const payload = buildClientBootstrapPayload()
    const validationError = validateClientBootstrapPayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    savingClientBootstrap.value = true
    try {
      await updateSystemSettings({ client_bootstrap: payload })
      applyClientBootstrapConfig(payload)
      ElMessage.success('入口容灾配置已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingClientBootstrap.value = false
    }
  }

  // 保存音视频接口设置
  const saveRTCSettings = async () => {
    const payload = buildRTCPayload()
    const validationError = validateRTCPayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    savingRTC.value = true
    try {
      await updateSystemSettings(payload)
      ElMessage.success('音视频接口设置已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingRTC.value = false
    }
  }

  // ==================== 协议文档 ====================

  // 保存用户协议
  const saveUserAgreement = async () => {
    savingAgreement.value = true
    try {
      await updateSystemSettings({ user_agreement: agreementForm.user_agreement })
      ElMessage.success('用户协议已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingAgreement.value = false
    }
  }

  // 保存隐私政策
  const savePrivacyPolicy = async () => {
    savingAgreement.value = true
    try {
      await updateSystemSettings({ privacy_policy: agreementForm.privacy_policy })
      ElMessage.success('隐私政策已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      savingAgreement.value = false
    }
  }

  // 预览协议（简单的 Markdown 转 HTML）
  const previewAgreement = (type: 'user' | 'privacy') => {
    const content = type === 'user' ? agreementForm.user_agreement : agreementForm.privacy_policy
    previewTitle.value = type === 'user' ? '用户协议预览' : '隐私政策预览'
    // 简单的 Markdown 转 HTML
    previewHtml.value = simpleMarkdownToHtml(content)
    previewDialogVisible.value = true
  }

  // 简单的 Markdown 转 HTML
  const simpleMarkdownToHtml = (md: string): string => {
    if (!md) return '<p class="text-gray-400">暂无内容</p>'
    const safeMd = escapeHtml(md)
    return (
      safeMd
        // 标题
        .replace(/^### (.*$)/gim, '<h3 class="text-lg font-semibold mt-4 mb-2">$1</h3>')
        .replace(/^## (.*$)/gim, '<h2 class="text-xl font-bold mt-6 mb-3">$1</h2>')
        .replace(/^# (.*$)/gim, '<h1 class="text-2xl font-bold mt-6 mb-4">$1</h1>')
        // 粗体和斜体
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
        .replace(/\*(.+?)\*/g, '<em>$1</em>')
        // 分隔线
        .replace(/^---$/gim, '<hr class="my-4 border-gray-300">')
        // 列表
        .replace(/^\d+\. (.*$)/gim, '<li class="ml-4">$1</li>')
        .replace(/^- (.*$)/gim, '<li class="ml-4 list-disc">$1</li>')
        // 段落
        .replace(/\n\n/g, '</p><p class="my-2">')
        .replace(/\n/g, '<br>')
        // 包装
        .replace(/^/, '<p class="my-2">')
        .replace(/$/, '</p>')
    )
  }

  const escapeHtml = (value: string): string =>
    value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')

  // ==================== 官方群组 ====================
  const loadOfficialGroups = async () => {
    loadingGroups.value = true
    try {
      officialGroups.value = (await getOfficialGroups()) || []
    } catch (error) {
      console.error('加载官方群组失败:', error)
    } finally {
      loadingGroups.value = false
    }
  }

  const showAddOfficialGroup = () => {
    addGroupForm.username = ''
    addGroupForm.remark = ''
    addGroupDialogVisible.value = true
  }

  const handleAddOfficialGroup = async () => {
    const input = addGroupForm.username.trim()
    if (!input) {
      ElMessage.warning('请输入群组 UUID 或用户名')
      return
    }
    addingGroup.value = true
    try {
      const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input)
      if (isUUID) {
        await addOfficialGroup(input, addGroupForm.remark)
      } else {
        await addOfficialGroupByUsername(input, addGroupForm.remark)
      }
      ElMessage.success('已添加官方群组')
      addGroupDialogVisible.value = false
      loadOfficialGroups()
    } catch (error: any) {
      ElMessage.error(error?.message || '添加失败')
    } finally {
      addingGroup.value = false
    }
  }

  const handleRemoveOfficialGroup = async (row: OfficialGroup) => {
    try {
      await ElMessageBox.confirm(`确定要移除官方群组 "${row.name}" 吗？`, '移除确认')
      await removeOfficialGroup(row.id)
      ElMessage.success('已移除')
      loadOfficialGroups()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('移除失败')
      }
    }
  }

  // ==================== 官方频道 ====================
  const loadOfficialChannels = async () => {
    loadingChannels.value = true
    try {
      officialChannels.value = (await getOfficialChannels()) || []
    } catch (error) {
      console.error('加载官方频道失败:', error)
    } finally {
      loadingChannels.value = false
    }
  }

  const showAddOfficialChannel = () => {
    addChannelForm.username = ''
    addChannelForm.remark = ''
    addChannelDialogVisible.value = true
  }

  const handleAddOfficialChannel = async () => {
    const input = addChannelForm.username.trim()
    if (!input) {
      ElMessage.warning('请输入频道 UUID 或用户名')
      return
    }
    addingChannel.value = true
    try {
      const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input)
      if (isUUID) {
        await addOfficialChannel(input, addChannelForm.remark)
      } else {
        await addOfficialChannelByUsername(input, addChannelForm.remark)
      }
      ElMessage.success('已添加官方频道')
      addChannelDialogVisible.value = false
      loadOfficialChannels()
    } catch (error: any) {
      ElMessage.error(error?.message || '添加失败')
    } finally {
      addingChannel.value = false
    }
  }

  const handleRemoveOfficialChannel = async (row: OfficialChannel) => {
    try {
      await ElMessageBox.confirm(`确定要移除官方频道 "${row.name}" 吗？`, '移除确认')
      await removeOfficialChannel(row.id)
      ElMessage.success('已移除')
      loadOfficialChannels()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('移除失败')
      }
    }
  }

  // 监听tab切换加载数据
  watch(activeTab, (tab) => {
    if (tab === 'official-groups' && officialGroups.value.length === 0) {
      loadOfficialGroups()
    } else if (tab === 'official-channels' && officialChannels.value.length === 0) {
      loadOfficialChannels()
    }
  })

  watch(
    () => route.name,
    () => {
      activeTab.value = getDefaultTabFromRoute()
    }
  )

  watch(
    () => basicForm.app_force_update,
    () => {
      basicFormRef.value?.validateField('app_update_url').catch(() => undefined)
    }
  )

  onMounted(() => {
    loadSettings()
  })
</script>

<style lang="scss" scoped>
  .settings-page {
    :deep(.el-tabs__content) {
      padding: 20px;
    }
  }

  .feature-settings-form {
    max-width: 1120px;
  }

  .attachment-menu-panel {
    padding: 20px;
    margin-bottom: 24px;
    overflow: hidden;
    background:
      radial-gradient(circle at 100% 0, rgb(59 130 246 / 9%), transparent 36%),
      linear-gradient(180deg, #fbfdff 0%, #f8fafc 100%);
    border: 1px solid #e2e8f0;
    border-radius: 16px;
  }

  .attachment-menu-header {
    display: flex;
    gap: 24px;
    align-items: center;
    justify-content: space-between;
    padding-bottom: 18px;
    margin-bottom: 16px;
    border-bottom: 1px solid #e8eef5;
  }

  .attachment-menu-heading {
    display: flex;
    gap: 14px;
    align-items: flex-start;
    min-width: 0;
  }

  .attachment-menu-heading__icon {
    display: inline-flex;
    flex: 0 0 44px;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    color: #2563eb;
    background: #eaf2ff;
    border-radius: 13px;
    box-shadow: inset 0 0 0 1px rgb(37 99 235 / 8%);
  }

  .attachment-menu-heading__icon :deep(svg) {
    width: 23px;
    height: 23px;
  }

  .attachment-menu-heading__meta {
    margin-bottom: 3px;
    font-size: 12px;
    font-weight: 700;
    color: #2563eb;
    letter-spacing: 0.08em;
  }

  .attachment-menu-heading h3 {
    margin: 0;
    font-size: 18px;
    font-weight: 700;
    line-height: 26px;
    color: #172033;
  }

  .attachment-menu-heading p {
    max-width: 610px;
    margin: 5px 0 0;
    font-size: 13px;
    line-height: 20px;
    color: #64748b;
  }

  .attachment-menu-master {
    display: flex;
    flex: 0 0 auto;
    gap: 14px;
    align-items: center;
    padding: 11px 14px;
    background: rgb(255 255 255 / 88%);
    border: 1px solid #dce5f0;
    border-radius: 12px;
    box-shadow: 0 6px 18px rgb(15 23 42 / 4%);
  }

  .attachment-menu-master__text {
    min-width: 132px;
    text-align: right;
  }

  .attachment-menu-master__text strong,
  .attachment-menu-master__text span {
    display: block;
  }

  .attachment-menu-master__text strong {
    font-size: 13px;
    font-weight: 650;
    line-height: 20px;
    color: #1e293b;
  }

  .attachment-menu-master__text span {
    margin-top: 1px;
    font-size: 12px;
    line-height: 18px;
    color: #94a3b8;
  }

  .attachment-menu-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
  }

  .attachment-menu-item {
    --attachment-accent: #3b82f6;
    --attachment-soft: #eff6ff;

    display: flex;
    gap: 12px;
    align-items: center;
    min-width: 0;
    min-height: 78px;
    padding: 14px;
    background: rgb(255 255 255 / 90%);
    border: 1px solid #e5ebf3;
    border-radius: 12px;
    transition:
      border-color 0.2s ease,
      box-shadow 0.2s ease,
      transform 0.2s ease;
  }

  .attachment-menu-item:hover {
    border-color: #cbd8e8;
    box-shadow: 0 8px 22px rgb(15 23 42 / 6%);
    transform: translateY(-1px);
  }

  .attachment-menu-item.is-active {
    border-color: color-mix(in srgb, var(--attachment-accent) 28%, #e5ebf3);
  }

  .attachment-menu-item--camera {
    --attachment-accent: #8b5cf6;
    --attachment-soft: #f3efff;
  }

  .attachment-menu-item--call {
    --attachment-accent: #06a77d;
    --attachment-soft: #eafaf5;
  }

  .attachment-menu-item--location {
    --attachment-accent: #f59e0b;
    --attachment-soft: #fff7e6;
  }

  .attachment-menu-item--packet,
  .attachment-menu-item--burn {
    --attachment-accent: #ef4444;
    --attachment-soft: #fff0f0;
  }

  .attachment-menu-item--transfer {
    --attachment-accent: #10b981;
    --attachment-soft: #eafaf3;
  }

  .attachment-menu-item--favorite {
    --attachment-accent: #ec8b17;
    --attachment-soft: #fff6e8;
  }

  .attachment-menu-item--file {
    --attachment-accent: #64748b;
    --attachment-soft: #f1f5f9;
  }

  .attachment-menu-item__icon {
    display: inline-flex;
    flex: 0 0 40px;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    color: var(--attachment-accent);
    background: var(--attachment-soft);
    border-radius: 11px;
  }

  .attachment-menu-item__icon :deep(svg) {
    width: 21px;
    height: 21px;
  }

  .attachment-menu-item__content {
    flex: 1 1 auto;
    min-width: 0;
  }

  .attachment-menu-item__content strong,
  .attachment-menu-item__content span {
    display: block;
  }

  .attachment-menu-item__content strong {
    overflow: hidden;
    font-size: 14px;
    font-weight: 650;
    line-height: 21px;
    color: #253045;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .attachment-menu-item__content span {
    margin-top: 2px;
    overflow: hidden;
    font-size: 12px;
    line-height: 18px;
    color: #8a98aa;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .attachment-menu-panel--disabled .attachment-menu-grid,
  .attachment-menu-panel--disabled .attachment-menu-notice {
    opacity: 0.58;
  }

  .attachment-menu-notice {
    display: flex;
    gap: 7px;
    align-items: flex-start;
    padding: 10px 12px;
    margin-top: 12px;
    font-size: 12px;
    line-height: 18px;
    color: #718096;
    background: rgb(241 245 249 / 78%);
    border-radius: 9px;
    transition: opacity 0.2s ease;
  }

  .attachment-menu-notice :deep(svg) {
    flex: 0 0 auto;
    width: 16px;
    height: 16px;
    margin-top: 1px;
    color: #64748b;
  }

  .feature-section-card {
    padding: 20px;
    margin-bottom: 16px;
    background: #fff;
    border: 1px solid #e4eaf2;
    border-radius: 16px;
    box-shadow: 0 8px 26px rgb(15 23 42 / 3%);
  }

  .feature-section-header {
    display: flex;
    gap: 13px;
    align-items: center;
    padding-bottom: 16px;
    margin-bottom: 14px;
    border-bottom: 1px solid #edf1f6;
  }

  .feature-section-header__icon {
    display: inline-flex;
    flex: 0 0 40px;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    color: #2563eb;
    background: #ebf3ff;
    border-radius: 12px;
  }

  .feature-section-header__icon :deep(svg) {
    width: 21px;
    height: 21px;
  }

  .feature-section-header > div {
    flex: 1 1 auto;
    min-width: 0;
  }

  .feature-section-header__eyebrow {
    display: block;
    margin-bottom: 1px;
    font-size: 11px;
    font-weight: 700;
    line-height: 17px;
    color: #2563eb;
    letter-spacing: 0.08em;
  }

  .feature-section-header h3 {
    margin: 0;
    font-size: 16px;
    font-weight: 700;
    line-height: 24px;
    color: #1c2739;
  }

  .feature-section-header p {
    margin: 3px 0 0;
    font-size: 12px;
    line-height: 19px;
    color: #7b899d;
  }

  .feature-section-card--security .feature-section-header__icon {
    color: #7c3aed;
    background: #f3efff;
  }

  .feature-section-card--security .feature-section-header__eyebrow {
    color: #7c3aed;
  }

  .feature-section-card--moment .feature-section-header__icon {
    color: #e48614;
    background: #fff5e7;
  }

  .feature-section-card--moment .feature-section-header__eyebrow {
    color: #d97706;
  }

  .feature-section-card--portal .feature-section-header__icon {
    color: #0891b2;
    background: #e9f9fc;
  }

  .feature-section-card--portal .feature-section-header__eyebrow {
    color: #0783a0;
  }

  .feature-section-card--new-user .feature-section-header__icon {
    color: #059669;
    background: #e9f9f3;
  }

  .feature-section-card--new-user .feature-section-header__eyebrow {
    color: #05805b;
  }

  .feature-section-card--group .feature-section-header__icon {
    color: #475569;
    background: #edf2f7;
  }

  .feature-section-card--group .feature-section-header__eyebrow {
    color: #526174;
  }

  .feature-setting-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
  }

  .feature-setting-grid--single {
    grid-template-columns: 1fr;
  }

  .feature-setting-grid--muted {
    opacity: 0.62;
  }

  .feature-setting-grid :deep(.el-form-item) {
    display: block;
    min-width: 0;
    min-height: 102px;
    padding: 13px 14px;
    margin: 0;
    background: #f8fafc;
    border: 1px solid #edf1f5;
    border-radius: 11px;
  }

  .feature-setting-grid :deep(.el-form-item__label) {
    justify-content: flex-start;
    width: auto !important;
    height: auto;
    min-height: 0;
    padding: 0 0 9px;
    font-size: 13px;
    font-weight: 600;
    line-height: 20px;
    color: #475569;
  }

  .feature-setting-grid :deep(.el-form-item__content) {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 10px;
    align-items: center;
    min-width: 0;
    min-height: 32px;
    margin-left: 0 !important;
    line-height: 20px;
  }

  .feature-setting-grid :deep(.el-input) {
    flex: 1 1 100%;
    min-width: 0;
  }

  .feature-setting-grid :deep(.el-input-number) {
    flex: 0 0 168px;
    width: 168px;
    max-width: 100%;
  }

  .feature-setting-grid__wide {
    grid-column: 1 / -1;
  }

  .feature-setting-help {
    flex: 1 1 180px;
    min-width: 0;
    font-size: 12px;
    line-height: 18px;
    color: #8a98aa;
    overflow-wrap: anywhere;
  }

  .feature-setting-help--block {
    flex-basis: 100%;
  }

  .feature-portal-upload {
    display: flex;
    gap: 10px;
    align-items: center;
  }

  .feature-portal-upload > span {
    font-size: 12px;
    line-height: 18px;
    color: #8a98aa;
  }

  .feature-portal-upload__preview {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    overflow: hidden;
    color: #94a3b8;
    cursor: pointer;
    background: #fff;
    border: 1px dashed #b8c3d1;
    border-radius: 12px;
  }

  .feature-portal-upload__preview img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .feature-portal-upload__preview :deep(svg) {
    width: 20px;
    height: 20px;
  }

  .feature-save-bar {
    position: sticky;
    bottom: 12px;
    z-index: 2;
    display: flex;
    gap: 24px;
    align-items: center;
    justify-content: space-between;
    padding: 14px 16px;
    margin-top: 20px;
    background: rgb(255 255 255 / 94%);
    backdrop-filter: blur(12px);
    border: 1px solid #dce4ee;
    border-radius: 14px;
    box-shadow: 0 12px 32px rgb(15 23 42 / 12%);
  }

  .feature-save-bar strong,
  .feature-save-bar span {
    display: block;
  }

  .feature-save-bar strong {
    font-size: 14px;
    line-height: 21px;
    color: #263246;
  }

  .feature-save-bar span {
    margin-top: 2px;
    font-size: 12px;
    line-height: 18px;
    color: #8492a6;
  }

  .feature-save-bar :deep(.el-button span) {
    display: inline-flex;
    gap: 7px;
    align-items: center;
    margin: 0;
    color: inherit;
  }

  .agreement-preview {
    max-height: 70vh;
    padding: 16px;
    overflow-y: auto;
    background: #fafafa;
    border-radius: 8px;

    h1,
    h2,
    h3 {
      color: #1f2937;
    }

    p {
      line-height: 1.6;
      color: #374151;
    }

    li {
      margin: 4px 0;
      color: #374151;
    }

    hr {
      border-color: #e5e7eb;
    }
  }

  .endpoint-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-bottom: 16px;
  }

  .failover-page {
    max-width: 1080px;
  }

  .failover-hero {
    display: flex;
    gap: 20px;
    align-items: flex-start;
    justify-content: space-between;
    padding: 20px;
    margin-bottom: 18px;
    background: #f8fafc;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
  }

  .failover-eyebrow {
    margin: 0 0 6px;
    font-size: 13px;
    font-weight: 600;
    color: #2563eb;
  }

  .failover-hero h3,
  .section-title h4 {
    margin: 0;
    color: #111827;
  }

  .failover-hero h3 {
    font-size: 20px;
    font-weight: 700;
  }

  .failover-hero p,
  .section-title p,
  .form-tip {
    margin: 6px 0 0;
    font-size: 13px;
    line-height: 1.6;
    color: #6b7280;
  }

  .failover-status {
    display: flex;
    flex: 0 0 auto;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: flex-end;
    min-width: 220px;
    font-size: 13px;
    color: #4b5563;
  }

  .failover-status span {
    padding: 4px 10px;
    background: #fff;
    border: 1px solid #e5e7eb;
    border-radius: 999px;
  }

  .storage-diagnostics {
    padding: 14px;
    margin-bottom: 18px;
    background: #f8fafc;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
  }

  .storage-diagnostics-head {
    display: flex;
    gap: 12px;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 12px;
  }

  .storage-kicker,
  .storage-diagnostics-grid span,
  .storage-test-result span {
    display: block;
    font-size: 12px;
    line-height: 18px;
    color: #64748b;
  }

  .storage-diagnostics-head strong {
    display: block;
    margin-top: 2px;
    font-size: 16px;
    line-height: 24px;
    color: #111827;
  }

  .storage-diagnostics-actions {
    display: flex;
    flex: 0 0 auto;
    gap: 8px;
  }

  .storage-diagnostics-grid,
  .storage-test-result {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 10px;
  }

  .storage-diagnostics-grid > div,
  .storage-test-result {
    padding: 10px;
    background: #fff;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .storage-diagnostics-grid b,
  .storage-test-result b {
    display: block;
    margin-top: 4px;
    overflow: hidden;
    font-size: 13px;
    font-weight: 600;
    color: #1f2937;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .storage-test-result {
    align-items: center;
    margin-top: 12px;
  }

  .upload-stage-metrics {
    margin-top: 14px;
    overflow: hidden;
    background: #fff;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .upload-stage-metrics__title {
    display: flex;
    gap: 10px;
    align-items: baseline;
    justify-content: space-between;
    padding: 10px 12px;
    color: #1f2937;
    border-bottom: 1px solid #edf2f7;
  }

  .upload-stage-metrics__title span {
    font-size: 12px;
    color: #64748b;
  }

  .failover-form {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .failover-section {
    padding: 18px;
    background: #fff;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
  }

  .section-title {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 16px;
  }

  .basic-setting-grid,
  .endpoint-card-grid,
  .strategy-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 14px;
  }

  .endpoint-cards,
  .media-url-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .endpoint-card {
    padding: 14px;
    background: #f9fafb;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .endpoint-card-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 12px;
  }

  .endpoint-card-head > div {
    display: flex;
    gap: 8px;
    align-items: center;
    min-width: 0;
  }

  .endpoint-name {
    overflow: hidden;
    font-size: 13px;
    color: #4b5563;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .media-url-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 56px;
    gap: 10px;
    align-items: center;
  }

  .strategy-presets {
    display: flex;
    gap: 10px;
    margin-bottom: 14px;
  }

  .failover-actions {
    display: flex;
    justify-content: flex-end;
  }

  .client-bootstrap-guide {
    padding: 18px;
    margin-bottom: 20px;
    background: #f8fafc;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
  }

  .guide-title {
    margin: 0 0 6px;
    font-size: 16px;
    font-weight: 600;
    color: #111827;
  }

  .guide-desc {
    max-width: 960px;
    margin: 0;
    line-height: 1.7;
    color: #4b5563;
  }

  .guide-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
    margin-top: 14px;
  }

  .guide-item {
    display: flex;
    gap: 10px;
    padding: 12px;
    background: #fff;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .guide-index {
    display: inline-flex;
    flex: 0 0 24px;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    font-size: 13px;
    font-weight: 700;
    color: #2563eb;
    background: #eff6ff;
    border-radius: 999px;
  }

  .guide-item strong {
    display: block;
    margin-bottom: 4px;
    color: #1f2937;
  }

  .guide-item p {
    margin: 0 0 6px;
    font-size: 13px;
    line-height: 1.6;
    color: #6b7280;
  }

  .guide-item code,
  .endpoint-help code {
    padding: 1px 5px;
    font-size: 12px;
    color: #2563eb;
    background: #eff6ff;
    border-radius: 4px;
  }

  .endpoint-help {
    margin: -6px 0 12px 52px;
    font-size: 13px;
    line-height: 1.7;
    color: #6b7280;
  }

  .endpoint-row {
    display: grid;
    gap: 10px;
    align-items: center;
  }

  .endpoint-row--api {
    grid-template-columns:
      minmax(120px, 0.7fr) minmax(260px, 2fr) 120px minmax(150px, 0.8fr)
      minmax(140px, 1fr) 56px;
  }

  .endpoint-row--ws {
    grid-template-columns: minmax(120px, 0.7fr) minmax(260px, 2fr) 120px minmax(150px, 0.8fr) 56px;
  }

  .endpoint-row-head,
  .media-row-head {
    font-size: 12px;
    font-weight: 600;
    color: #6b7280;
  }

  .media-row {
    display: grid;
    grid-template-columns: minmax(320px, 1fr) 56px;
    gap: 10px;
    align-items: center;
  }

  @media (width <= 1200px) {
    .failover-hero,
    .section-title {
      flex-direction: column;
    }

    .failover-status {
      justify-content: flex-start;
      min-width: 0;
    }

    .basic-setting-grid,
    .endpoint-card-grid,
    .strategy-grid,
    .storage-diagnostics-grid,
    .storage-test-result,
    .media-url-row {
      grid-template-columns: 1fr;
    }

    .attachment-menu-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .endpoint-row,
    .endpoint-row--api,
    .endpoint-row--ws,
    .media-row {
      grid-template-columns: 1fr;
    }

    .endpoint-row-head,
    .media-row-head {
      display: none;
    }

    .endpoint-help {
      margin-left: 0;
    }
  }

  @media (width <= 960px) {
    .guide-grid {
      grid-template-columns: 1fr;
    }

    .feature-setting-grid {
      grid-template-columns: 1fr;
    }

    .feature-setting-grid__wide {
      grid-column: auto;
    }

    .attachment-menu-header {
      flex-direction: column;
      align-items: stretch;
    }

    .attachment-menu-master {
      justify-content: space-between;
    }

    .attachment-menu-master__text {
      text-align: left;
    }
  }

  @media (width <= 680px) {
    .attachment-menu-panel {
      padding: 16px;
      border-radius: 12px;
    }

    .attachment-menu-grid {
      grid-template-columns: 1fr;
    }

    .attachment-menu-heading__icon {
      display: none;
    }

    .feature-section-card {
      padding: 16px;
      border-radius: 12px;
    }

    .feature-section-header {
      flex-wrap: wrap;
    }

    .feature-section-header p {
      display: none;
    }

    .feature-save-bar {
      flex-direction: column;
      gap: 12px;
      align-items: stretch;
    }

    .feature-save-bar :deep(.el-button) {
      width: 100%;
    }
  }

  :deep(.dark) .agreement-preview {
    background: #1f2937;

    h1,
    h2,
    h3 {
      color: #f9fafb;
    }

    p,
    li {
      color: #d1d5db;
    }

    hr {
      border-color: #374151;
    }
  }

  :deep(.dark) .attachment-menu-panel {
    background:
      radial-gradient(circle at 100% 0, rgb(59 130 246 / 12%), transparent 36%),
      linear-gradient(180deg, #182131 0%, #151d2a 100%);
    border-color: #2b3749;
  }

  :deep(.dark) .attachment-menu-header {
    border-bottom-color: #2b3749;
  }

  :deep(.dark) .attachment-menu-heading h3,
  :deep(.dark) .attachment-menu-master__text strong,
  :deep(.dark) .attachment-menu-item__content strong {
    color: #e7edf6;
  }

  :deep(.dark) .attachment-menu-heading p,
  :deep(.dark) .attachment-menu-master__text span,
  :deep(.dark) .attachment-menu-item__content span,
  :deep(.dark) .attachment-menu-notice {
    color: #91a0b5;
  }

  :deep(.dark) .attachment-menu-master,
  :deep(.dark) .attachment-menu-item {
    background: rgb(23 32 47 / 92%);
    border-color: #303d50;
  }

  :deep(.dark) .attachment-menu-item:hover {
    border-color: #46566d;
    box-shadow: 0 8px 22px rgb(0 0 0 / 18%);
  }

  :deep(.dark) .attachment-menu-notice {
    background: rgb(30 41 59 / 72%);
  }

  :deep(.dark) .feature-section-card {
    background: #171f2d;
    border-color: #2c384b;
    box-shadow: 0 8px 26px rgb(0 0 0 / 10%);
  }

  :deep(.dark) .feature-section-header {
    border-bottom-color: #2b3749;
  }

  :deep(.dark) .feature-section-header h3,
  :deep(.dark) .feature-setting-grid .el-form-item__label,
  :deep(.dark) .feature-save-bar strong {
    color: #e5ebf4;
  }

  :deep(.dark) .feature-section-header p,
  :deep(.dark) .feature-setting-help,
  :deep(.dark) .feature-portal-upload > span,
  :deep(.dark) .feature-save-bar span {
    color: #91a0b5;
  }

  :deep(.dark) .feature-setting-grid .el-form-item {
    background: #1d2736;
    border-color: #2c394c;
  }

  :deep(.dark) .feature-portal-upload__preview {
    color: #8190a5;
    background: #151d29;
    border-color: #46556a;
  }

  :deep(.dark) .feature-save-bar {
    background: rgb(23 31 45 / 94%);
    border-color: #344257;
    box-shadow: 0 12px 32px rgb(0 0 0 / 22%);
  }
</style>
