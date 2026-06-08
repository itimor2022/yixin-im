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
          <ElFormItem label="邀请注册链接域名" prop="register_base_url">
            <ElInput
              v-model="basicForm.register_base_url"
              placeholder="如：https://app.example.com"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >客户端“邀请朋友”链接会使用该域名；留空则使用后端配置文件中的注册页域名</span
            >
          </ElFormItem>
          <ElDivider content-position="left">App版本</ElDivider>
          <ElFormItem label="iOS版本号" prop="app_version_ios">
            <ElInput
              v-model="basicForm.app_version_ios"
              placeholder="如：1.0.0"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >留空时保存将自动使用“系统版本”，格式如 1.0.0 或 1.0.0-beta.1</span
            >
          </ElFormItem>
          <ElFormItem label="Android版本号" prop="app_version_android">
            <ElInput
              v-model="basicForm.app_version_android"
              placeholder="如：1.0.0"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >留空时保存将自动使用“系统版本”，格式如 1.0.0 或 1.0.0-beta.1</span
            >
          </ElFormItem>
          <ElFormItem label="强制更新">
            <ElSwitch v-model="basicForm.app_force_update" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后用户必须更新才能使用</span>
          </ElFormItem>
          <ElFormItem label="更新下载链接" prop="app_update_url">
            <ElInput
              v-model="basicForm.app_update_url"
              placeholder="App Store / 下载页面链接"
              :disabled="isDemoAdmin"
            />
            <span class="mt-1 text-xs text-g-400"
              >开启强制更新时该项必填；请使用完整链接，如 https://example.com/app</span
            >
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
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="savingBasic" @click="saveBasicSettings">
              保存设置
            </ElButton>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- 功能设置 -->
      <ElTabPane label="功能设置" name="features">
        <!-- 演示管理员提示 -->
        <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
          您当前是演示管理员，只能查看设置，无法进行修改。敏感配置已隐藏。
        </ElAlert>
        <ElForm :model="featureForm" label-width="180px" class="max-w-2xl">
          <ElFormItem label="阅后即焚">
            <ElSwitch v-model="featureForm.burn_after_read_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">
              关闭后所有客户端隐藏阅后即焚入口，后端也会忽略旧版本客户端携带的阅后即焚标记
            </span>
          </ElFormItem>
          <ElDivider content-position="left">注册与安全</ElDivider>
          <ElFormItem label="允许新用户注册">
            <ElSwitch v-model="featureForm.allow_register" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">关闭后新用户无法注册账号</span>
          </ElFormItem>
          <ElFormItem label="注册必须填写邀请码">
            <ElSwitch v-model="featureForm.require_invite_code" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后新用户注册时必须填写有效邀请码</span>
          </ElFormItem>
          <ElFormItem label="强制绑定手机号">
            <ElSwitch v-model="featureForm.require_phone_bind" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400"
              >开启后用户登录后必须先绑定手机号，未绑定前不可使用消息、通讯录、钱包等功能</span
            >
          </ElFormItem>
          <ElDivider content-position="left">广场功能</ElDivider>
          <ElFormItem label="允许发布动态">
            <ElSwitch v-model="featureForm.enable_moment_post" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">关闭后用户只能浏览动态，不能发布</span>
          </ElFormItem>
          <ElFormItem label="动态发布审核">
            <ElSwitch v-model="featureForm.moment_post_review_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400"
              >开启后用户发布动态需后台审核通过后才会在广场展示</span
            >
          </ElFormItem>
          <ElDivider content-position="left">客户端自定义栏目</ElDivider>
          <ElFormItem label="启用自定义栏目">
            <ElSwitch v-model="featureForm.custom_portal_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400"
              >开启后，会在客户端“联系人”和“发现”之间显示一个可自定义的网站入口</span
            >
          </ElFormItem>
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
            <div class="flex items-center gap-3">
              <ElUpload
                :action="portalUploadUrl"
                :headers="portalUploadHeaders"
                :show-file-list="false"
                accept="image/*"
                :disabled="!featureForm.custom_portal_enabled || isDemoAdmin"
                :on-success="handlePortalIconUploadSuccess"
              >
                <div
                  class="flex h-11 w-11 cursor-pointer items-center justify-center overflow-hidden rounded-xl border border-dashed border-g-300 bg-g-50"
                >
                  <img
                    v-if="featureForm.custom_portal_icon_url"
                    :src="fixImageUrl(featureForm.custom_portal_icon_url)"
                    alt="portal-icon"
                    class="h-full w-full object-cover"
                  />
                  <ArtSvgIcon v-else icon="ri:image-add-line" class="text-g-400 text-lg" />
                </div>
              </ElUpload>
              <div class="text-xs text-g-400">点击上传图标，建议使用 64x64 正方形图片</div>
            </div>
          </ElFormItem>
          <ElFormItem label="打开网址">
            <ElInput
              v-model="featureForm.custom_portal_url"
              placeholder="例如：https://example.com"
              :disabled="!featureForm.custom_portal_enabled || isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">部分网站会限制内嵌显示；若页面空白，客户端会提供直接打开入口</span>
          </ElFormItem>
          <ElDivider content-position="left">在线客服</ElDivider>
          <ElFormItem label="在线客服地址">
            <ElInput
              v-model="featureForm.customer_service_url"
              placeholder="例如：https://kefu.example.com 或 https://t.me/xxx"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">App「找回密码」与「常见问题-在线客服」会跳转此地址</span>
          </ElFormItem>
          <ElDivider content-position="left">新用户设置</ElDivider>
          <ElFormItem label="新用户强制关注官方用户">
            <ElSwitch v-model="featureForm.new_user_follow_official" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="邀请码只加绑定客服">
            <ElSwitch v-model="featureForm.invite_register_bind_only" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400"
              >开启后，邀请码注册用户只自动添加该邀请码绑定客服</span
            >
          </ElFormItem>
          <ElFormItem label="新用户强制加入官方群组">
            <ElSwitch v-model="featureForm.new_user_join_group" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="新用户强制订阅官方频道">
            <ElSwitch v-model="featureForm.new_user_join_channel" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElDivider content-position="left">群组与频道</ElDivider>
          <ElFormItem label="非好友不可拉群">
            <ElSwitch v-model="featureForm.group_invite_require_friend" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="仅会员可建群">
            <ElSwitch v-model="featureForm.member_only_create_group" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后非会员无法创建群组和频道</span>
          </ElFormItem>
          <ElFormItem label="签到功能">
            <ElSwitch v-model="featureForm.checkin_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后客户端"设置"页显示每日签到入口</span>
          </ElFormItem>
          <ElFormItem label="非好友消息">
            <ElSwitch v-model="featureForm.allow_stranger_message" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">关闭后非好友只能加好友、不能直接发消息</span>
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
            <span class="ml-2 text-sm text-g-400">默认200000人</span>
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
            <span class="ml-2 text-sm text-g-400">0表示无限制</span>
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
            <span class="ml-2 text-sm text-g-400">分钟，默认2分钟</span>
          </ElFormItem>
          <ElFormItem label="IP发送消息频率限制">
            <ElInputNumber
              v-model="featureForm.ip_rate_limit"
              :min="0"
              :max="10000"
              :step="10"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">条/分钟（同一IP），0 表示不限制，默认60</span>
          </ElFormItem>
          <ElFormItem label="用户发消息频率限制">
            <ElInputNumber
              v-model="featureForm.user_rate_limit"
              :min="0"
              :max="10000"
              :step="10"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <span class="ml-2 text-sm text-g-400">条/分钟（单个用户），0 表示不限制，默认30</span>
          </ElFormItem>
          <ElFormItem label="消息加密模式">
            <ElRadioGroup v-model="featureForm.message_crypto_mode" :disabled="isDemoAdmin">
              <ElRadio value="plain">明文模式</ElRadio>
              <ElRadio value="compatible">兼容加密</ElRadio>
              <ElRadio value="strict">严格加密</ElRadio>
            </ElRadioGroup>
            <div class="ml-2 text-sm text-g-400">
              明文模式：后台可查明文；兼容加密：优先端到端加密，失败时回退明文；严格加密：仅允许发送端到端加密消息。
            </div>
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
          <ElDivider content-position="left">音视频通话（声网）</ElDivider>
          <ElFormItem label="启用音视频通话">
            <ElSwitch v-model="featureForm.agora_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后用户可进行语音/视频通话</span>
          </ElFormItem>
          <ElFormItem label="App ID">
            <ElInput
              v-model="featureForm.agora_app_id"
              :placeholder="isDemoAdmin ? '******' : '声网控制台获取的 App ID'"
              :disabled="!featureForm.agora_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="App Certificate">
            <ElInput
              v-model="featureForm.agora_app_certificate"
              :placeholder="isDemoAdmin ? '******' : '声网控制台获取的 App Certificate'"
              type="password"
              :show-password="!isDemoAdmin"
              :disabled="!featureForm.agora_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Token 有效期">
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
          <ElDivider content-position="left">iOS 推送通知（APNs）</ElDivider>
          <ElFormItem label="启用 APNs 推送">
            <ElSwitch v-model="featureForm.apns_enabled" :disabled="isDemoAdmin" />
            <span class="ml-2 text-sm text-g-400">开启后 iOS 设备可收到离线推送</span>
          </ElFormItem>
          <ElFormItem label="Bundle ID">
            <ElInput
              v-model="featureForm.apns_bundle_id"
              :placeholder="isDemoAdmin ? '******' : '如：com.example.app'"
              :disabled="!featureForm.apns_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Key ID">
            <ElInput
              v-model="featureForm.apns_key_id"
              :placeholder="isDemoAdmin ? '******' : '10位 Key ID'"
              :disabled="!featureForm.apns_enabled || isDemoAdmin"
              maxlength="10"
            />
          </ElFormItem>
          <ElFormItem label="Team ID">
            <ElInput
              v-model="featureForm.apns_team_id"
              :placeholder="isDemoAdmin ? '******' : '10位 Team ID'"
              :disabled="!featureForm.apns_enabled || isDemoAdmin"
              maxlength="10"
            />
          </ElFormItem>
          <ElFormItem label="Auth Key (.p8)">
            <ElInput
              v-model="featureForm.apns_auth_key"
              type="textarea"
              :rows="4"
              :placeholder="
                isDemoAdmin
                  ? '******（演示管理员无法查看）'
                  : '粘贴 .p8 文件的完整内容（包含 -----BEGIN PRIVATE KEY-----）'
              "
              :disabled="!featureForm.apns_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="环境">
            <ElRadioGroup
              v-model="featureForm.apns_environment"
              :disabled="!featureForm.apns_enabled || isDemoAdmin"
            >
              <ElRadio value="development">开发环境 (Sandbox)</ElRadio>
              <ElRadio value="production">生产环境 (Production)</ElRadio>
            </ElRadioGroup>
          </ElFormItem>
          <ElDivider content-position="left">Android 推送（多通道）</ElDivider>
          <ElFormItem label="启用 FCM">
            <ElSwitch v-model="featureForm.fcm_enabled" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="FCM Project ID">
            <ElInput
              v-model="featureForm.fcm_project_id"
              :placeholder="isDemoAdmin ? '******' : 'Firebase Project ID'"
              :disabled="!featureForm.fcm_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="FCM Service Account JSON">
            <ElInput
              v-model="featureForm.fcm_service_account_json"
              type="textarea"
              :rows="4"
              :placeholder="
                isDemoAdmin ? '******（演示管理员无法查看）' : '粘贴 Firebase service account JSON'
              "
              :disabled="!featureForm.fcm_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="启用 HMS">
            <ElSwitch v-model="featureForm.hms_enabled" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="HMS App ID">
            <ElInput
              v-model="featureForm.hms_app_id"
              :placeholder="isDemoAdmin ? '******' : '华为推送 App ID'"
              :disabled="!featureForm.hms_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="HMS App Secret">
            <ElInput
              v-model="featureForm.hms_app_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : '华为推送 App Secret'"
              :disabled="!featureForm.hms_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="启用小米推送">
            <ElSwitch v-model="featureForm.xiaomi_push_enabled" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="小米包名">
            <ElInput
              v-model="featureForm.xiaomi_package_name"
              :placeholder="isDemoAdmin ? '******' : '如：com.yixinim.app'"
              :disabled="!featureForm.xiaomi_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="小米 App Secret">
            <ElInput
              v-model="featureForm.xiaomi_app_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : '小米推送 App Secret'"
              :disabled="!featureForm.xiaomi_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="启用 OPPO 推送">
            <ElSwitch v-model="featureForm.oppo_push_enabled" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="OPPO App Key">
            <ElInput
              v-model="featureForm.oppo_app_key"
              :placeholder="isDemoAdmin ? '******' : 'OPPO 推送 App Key'"
              :disabled="!featureForm.oppo_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="OPPO App Secret">
            <ElInput
              v-model="featureForm.oppo_app_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : 'OPPO 推送 App Secret'"
              :disabled="!featureForm.oppo_push_enabled || isDemoAdmin"
            />
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
            <ElButton type="primary" :loading="saving" @click="saveFeatureSettings">
              保存设置
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
    OfficialGroup,
    OfficialChannel
  } from '@/api/admin'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import type { FormInstance, FormRules } from 'element-plus'
  import { fixImageUrl, getAvatarUrl } from '@/utils/url'
  import { useSettingStore } from '@/store/modules/setting'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'SystemSettings' })

  const settingStore = useSettingStore()
  const userStore = useUserStore()

  // 是否是演示管理员（只能查看，不能编辑）
  const isDemoAdmin = ref(false)
  const adminRole = ref('')

  const activeTab = ref('basic')
  const saving = ref(false)

  // 基本信息
  const basicForm = reactive({
    system_name: '',
    system_version: '',
    register_base_url: '',
    app_version_ios: '',
    app_version_android: '',
    app_force_update: false,
    app_update_url: '',
    app_update_message: ''
  })
  const savingBasic = ref(false)
  const basicFormRef = ref<FormInstance>()

  // 功能设置
  const featureForm = reactive({
    allow_register: true,
    require_invite_code: false,
    require_phone_bind: false,
    enable_moment_post: true,
    moment_post_review_enabled: false,
    new_user_follow_official: false,
    invite_register_bind_only: false,
    new_user_join_group: false,
    new_user_join_channel: false,
    group_invite_require_friend: false,
    member_only_create_group: false,
    checkin_enabled: false,
    allow_stranger_message: false,
    custom_portal_enabled: false,
    custom_portal_title: '',
    custom_portal_url: '',
    custom_portal_icon_url: '',
    customer_service_url: '',
    burn_after_read_enabled: true,
    message_crypto_mode: 'plain',
    group_max_members: 200000,
    channel_max_members: 0,
    revoke_message_minutes: 2,
    ip_rate_limit: 60,
    user_rate_limit: 30,
    heartbeat_timeout: 60,
    // 声网配置
    agora_enabled: false,
    agora_app_id: '',
    agora_app_certificate: '',
    agora_token_expire: 3600,
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
        callback(new Error('邀请注册链接域名必须以 http:// 或 https:// 开头'))
        return
      }
      callback()
    } catch {
      callback(new Error('请输入有效的邀请注册链接域名'))
    }
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
    app_version_ios: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    app_version_android: [{ validator: validateVersionValue, trigger: ['blur', 'change'] }],
    app_update_url: [{ validator: validateUpdateUrl, trigger: ['blur', 'change'] }],
    app_update_message: [{ validator: validateUpdateMessage, trigger: ['blur', 'change'] }]
  }

  const getEffectiveVersionPayload = () => {
    const systemVersion = basicForm.system_version.trim()
    return {
      system_name: basicForm.system_name,
      system_version: systemVersion,
      register_base_url: basicForm.register_base_url.trim().replace(/\/+$/, ''),
      app_version_ios: basicForm.app_version_ios.trim() || systemVersion,
      app_version_android: basicForm.app_version_android.trim() || systemVersion,
      app_force_update: basicForm.app_force_update,
      app_update_url: basicForm.app_update_url.trim(),
      app_update_message: basicForm.app_update_message.trim()
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
      if (settings.system_name) {
        settingStore.setSystemName(settings.system_name)
      }
      // 版本设置
      basicForm.app_version_ios = settings.app_version_ios || ''
      basicForm.app_version_android = settings.app_version_android || ''
      basicForm.app_force_update = settings.app_force_update || false
      basicForm.app_update_url = settings.app_update_url || ''
      basicForm.app_update_message = settings.app_update_message || ''
      // 功能设置
      featureForm.allow_register = settings.allow_register !== false
      featureForm.require_invite_code = settings.require_invite_code || false
      featureForm.require_phone_bind = settings.require_phone_bind || false
      featureForm.enable_moment_post = settings.enable_moment_post !== false
      featureForm.moment_post_review_enabled = settings.moment_post_review_enabled || false
      featureForm.new_user_follow_official = settings.new_user_follow_official || false
      featureForm.invite_register_bind_only = settings.invite_register_bind_only || false
      featureForm.new_user_join_group = settings.new_user_join_group || false
      featureForm.new_user_join_channel = settings.new_user_join_channel || false
      featureForm.group_invite_require_friend = settings.group_invite_require_friend || false
      featureForm.member_only_create_group = settings.member_only_create_group || false
      featureForm.checkin_enabled = settings.checkin_enabled || false
      featureForm.allow_stranger_message = settings.allow_stranger_message || false
      featureForm.custom_portal_enabled = settings.custom_portal_enabled || false
      featureForm.custom_portal_title = settings.custom_portal_title || ''
      featureForm.custom_portal_url = settings.custom_portal_url || ''
      featureForm.custom_portal_icon_url = settings.custom_portal_icon_url || ''
      featureForm.customer_service_url = settings.customer_service_url || ''
      featureForm.burn_after_read_enabled = settings.burn_after_read_enabled !== false
      featureForm.message_crypto_mode = settings.message_crypto_mode || 'plain'
      featureForm.group_max_members = settings.group_max_members ?? 200000
      featureForm.channel_max_members = settings.channel_max_members ?? 0
      featureForm.revoke_message_minutes = settings.revoke_message_minutes ?? 2
      featureForm.ip_rate_limit = settings.ip_rate_limit ?? 60
      featureForm.user_rate_limit = settings.user_rate_limit ?? 30
      featureForm.heartbeat_timeout = settings.heartbeat_timeout ?? 60
      // 声网配置
      featureForm.agora_enabled = settings.agora_enabled || false
      featureForm.agora_app_id = settings.agora_app_id || ''
      featureForm.agora_app_certificate = settings.agora_app_certificate || ''
      featureForm.agora_token_expire = settings.agora_token_expire ?? 3600
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

  const buildFeaturePayload = () => {
    return {
      ...featureForm,
      apns_bundle_id: featureForm.apns_bundle_id.trim(),
      apns_key_id: featureForm.apns_key_id.trim(),
      apns_team_id: featureForm.apns_team_id.trim(),
      apns_auth_key: featureForm.apns_auth_key.trim(),
      apns_environment: featureForm.apns_environment.trim().toLowerCase(),
      fcm_project_id: featureForm.fcm_project_id.trim(),
      fcm_service_account_json: featureForm.fcm_service_account_json.trim(),
      hms_app_id: featureForm.hms_app_id.trim(),
      hms_app_secret: featureForm.hms_app_secret.trim(),
      xiaomi_package_name: featureForm.xiaomi_package_name.trim(),
      xiaomi_app_secret: featureForm.xiaomi_app_secret.trim(),
      oppo_app_key: featureForm.oppo_app_key.trim(),
      oppo_app_secret: featureForm.oppo_app_secret.trim(),
      custom_portal_title: featureForm.custom_portal_title.trim(),
      custom_portal_url: featureForm.custom_portal_url.trim(),
      custom_portal_icon_url: featureForm.custom_portal_icon_url.trim(),
      message_crypto_mode: featureForm.message_crypto_mode
    }
  }

  const validatePushFeaturePayload = (
    payload: ReturnType<typeof buildFeaturePayload>
  ): string | null => {
    if (payload.apns_enabled) {
      if (
        !payload.apns_bundle_id ||
        !payload.apns_key_id ||
        !payload.apns_team_id ||
        !payload.apns_auth_key
      ) {
        return '启用 APNs 推送时，Bundle ID / Key ID / Team ID / Auth Key 不能为空'
      }
      if (!['development', 'production'].includes(payload.apns_environment)) {
        return 'APNs 环境仅支持 development 或 production'
      }
    }

    if (payload.fcm_enabled) {
      if (!payload.fcm_project_id || !payload.fcm_service_account_json) {
        return '启用 FCM 推送时，Project ID 与 Service Account JSON 不能为空'
      }
      const projectId = payload.fcm_project_id.trim()
      const normalizedProjectId = projectId.toLowerCase()
      if (
        projectId.startsWith('1:') ||
        normalizedProjectId.includes(':android:') ||
        normalizedProjectId.includes(':ios:')
      ) {
        return 'FCM Project ID 填写错误，请填写 Firebase Project ID（如 timi-9125c），不要填写 mobilesdk_app_id'
      }

      try {
        const serviceAccount = JSON.parse(payload.fcm_service_account_json) as {
          project_id?: string
          client_email?: string
          private_key?: string
        }
        const serviceProjectId = (serviceAccount.project_id || '').trim()
        if (!serviceProjectId) {
          return 'FCM Service Account JSON 缺少 project_id'
        }
        if (!serviceAccount.client_email || !serviceAccount.private_key) {
          return 'FCM Service Account JSON 缺少 client_email 或 private_key'
        }
        if (serviceProjectId !== projectId) {
          return 'FCM Project ID 与 Service Account JSON 的 project_id 不一致'
        }
      } catch {
        return 'FCM Service Account JSON 格式错误'
      }
    }

    if (payload.hms_enabled && (!payload.hms_app_id || !payload.hms_app_secret)) {
      return '启用 HMS 推送时，App ID 与 App Secret 不能为空'
    }
    if (
      payload.xiaomi_push_enabled &&
      (!payload.xiaomi_package_name || !payload.xiaomi_app_secret)
    ) {
      return '启用小米推送时，包名与 App Secret 不能为空'
    }
    if (payload.oppo_push_enabled && (!payload.oppo_app_key || !payload.oppo_app_secret)) {
      return '启用 OPPO 推送时，App Key 与 App Secret 不能为空'
    }
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

    return null
  }

  // 保存功能设置
  const saveFeatureSettings = async () => {
    const payload = buildFeaturePayload()
    const validationError = validatePushFeaturePayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    saving.value = true
    try {
      await updateSystemSettings(payload)
      ElMessage.success('功能设置已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      saving.value = false
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

  .agreement-preview {
    max-height: 70vh;
    overflow-y: auto;
    padding: 16px;
    background: #fafafa;
    border-radius: 8px;

    h1,
    h2,
    h3 {
      color: #1f2937;
    }

    p {
      color: #374151;
      line-height: 1.6;
    }

    li {
      color: #374151;
      margin: 4px 0;
    }

    hr {
      border-color: #e5e7eb;
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
</style>
