<template>
  <div class="vip-page p-4">
    <ElAlert
      class="mb-4"
      type="warning"
      show-icon
      :closable="false"
      title="VIP 购买当前使用钱包余额扣款"
      description="如果要接微信/支付宝生产支付，还需要完成商户参数、回调验签、订单补偿和退款闭环。"
    />

    <ElAlert
      v-if="pageError"
      class="mb-4"
      type="error"
      show-icon
      :title="pageError"
      @close="pageError = ''"
    />

    <div class="vip-overview mb-4">
      <div class="vip-stat-card">
        <div class="vip-stat-label">启用套餐</div>
        <div class="vip-stat-value">{{ enabledPlanCount }}/{{ plans.length }}</div>
      </div>
      <div class="vip-stat-card">
        <div class="vip-stat-label">会员用户</div>
        <div class="vip-stat-value">{{ userTotal }}</div>
      </div>
      <div class="vip-stat-card">
        <div class="vip-stat-label">当前页有效</div>
        <div class="vip-stat-value">{{ activeVipUserCount }}</div>
      </div>
      <div class="vip-stat-card">
        <div class="vip-stat-label">当前页 SVIP</div>
        <div class="vip-stat-value">{{ activeSvipUserCount }}</div>
      </div>
      <div class="vip-stat-card">
        <div class="vip-stat-label">当前页冻结</div>
        <div class="vip-stat-value">{{ frozenVipUserCount }}</div>
      </div>
    </div>

    <ElTabs v-model="activeTab" type="border-card">
      <ElTabPane label="普通用户额度" name="free">
        <div
          class="mb-4 flex items-center justify-between gap-3 max-md:flex-col max-md:items-stretch"
        >
          <div class="text-sm text-g-500">
            配置未开通会员用户的建群、频道、容量和高级能力。保存后立即影响后端创建校验。
          </div>
          <div class="flex items-center gap-2">
            <ElButton @click="loadFreeEntitlements" :loading="freeLoading">
              <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
              刷新
            </ElButton>
            <ElButton
              type="primary"
              @click="saveFreeEntitlements"
              :loading="freeSaving"
              :disabled="isDemoAdmin"
            >
              保存
            </ElButton>
          </div>
        </div>

        <ElForm :model="freeBenefits" label-width="120px" v-loading="freeLoading">
          <ElDivider content-position="left">创建与人数</ElDivider>
          <ElFormItem label="可创建">
            <ElSwitch v-model="freeBenefits.can_create_group" active-text="群聊" />
            <ElSwitch
              v-model="freeBenefits.can_create_channel"
              active-text="频道"
              class="ml-5"
            />
          </ElFormItem>
          <ElFormItem label="数量上限">
            <ElInputNumber
              v-model="freeBenefits.max_owned_groups"
              :min="0"
              controls-position="right"
              :disabled="!freeBenefits.can_create_group"
            />
            <span class="mx-3 text-g-400">群</span>
            <ElInputNumber
              v-model="freeBenefits.max_owned_channels"
              :min="0"
              controls-position="right"
              :disabled="!freeBenefits.can_create_channel"
            />
            <span class="ml-3 text-g-400">频道</span>
          </ElFormItem>
          <ElFormItem label="成员上限">
            <ElInputNumber
              v-model="freeBenefits.max_group_members"
              :min="0"
              controls-position="right"
              :disabled="!freeBenefits.can_create_group"
            />
            <span class="mx-3 text-g-400">群成员</span>
            <ElInputNumber
              v-model="freeBenefits.max_channel_members"
              :min="0"
              controls-position="right"
              :disabled="!freeBenefits.can_create_channel"
            />
            <span class="ml-3 text-g-400">频道订阅</span>
          </ElFormItem>
          <ElDivider content-position="left">容量与高级能力</ElDivider>
          <ElFormItem label="会话置顶">
            <ElInputNumber
              v-model="freeBenefits.max_pinned_chats"
              :min="0"
              controls-position="right"
            />
          </ElFormItem>
          <ElFormItem label="上传上限">
            <ElInputNumber
              v-model="freeBenefits.upload_image_limit_mb"
              :min="0"
              controls-position="right"
            />
            <span class="mx-2 text-g-400">图片 MB</span>
            <ElInputNumber
              v-model="freeBenefits.upload_video_limit_mb"
              :min="0"
              controls-position="right"
            />
            <span class="mx-2 text-g-400">视频 MB</span>
            <ElInputNumber
              v-model="freeBenefits.upload_file_limit_mb"
              :min="0"
              controls-position="right"
            />
            <span class="mx-2 text-g-400">文件 MB</span>
            <ElInputNumber
              v-model="freeBenefits.upload_voice_limit_mb"
              :min="0"
              controls-position="right"
            />
            <span class="ml-2 text-g-400">语音 MB</span>
          </ElFormItem>
          <ElFormItem label="高级能力">
            <ElSwitch v-model="freeBenefits.can_set_public_username" active-text="公开群号" />
            <ElSwitch
              v-model="freeBenefits.can_enable_member_protection"
              active-text="成员保护"
              class="ml-5"
            />
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <ElTabPane label="套餐设置" name="plans">
        <div
          class="mb-4 flex items-center justify-between gap-3 max-md:flex-col max-md:items-stretch"
        >
          <div class="text-sm text-g-500">管理 App 展示的 VIP/SVIP 套餐、价格和权益上限。</div>
          <div class="flex items-center gap-2">
            <ElButton @click="loadPlans" :loading="planLoading">
              <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
              刷新
            </ElButton>
            <ElButton type="primary" @click="openPlanDialog()" :disabled="isDemoAdmin">
              <ArtSvgIcon icon="ri:add-line" class="mr-1" />
              新增套餐
            </ElButton>
          </div>
        </div>

        <ElTable :data="plans" v-loading="planLoading" stripe border>
          <ElTableColumn prop="sort" label="顺序" width="80" align="center" />
          <ElTableColumn label="套餐" min-width="180">
            <template #default="{ row }">
              <div class="flex items-center gap-2">
                <span class="font-medium">{{ row.name }}</span>
                <span :class="['vip-badge', row.level >= 2 ? 'svip' : 'vip']">
                  {{ row.level_name }}
                </span>
              </div>
              <div class="mt-1 text-xs text-g-400">{{ row.code }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="有效期" width="100" align="center">
            <template #default="{ row }">{{ row.duration_days }} 天</template>
          </ElTableColumn>
          <ElTableColumn label="价格" width="140" align="right">
            <template #default="{ row }">
              <span class="font-semibold">¥{{ money(row.price) }}</span>
              <span
                v-if="row.original_price > row.price"
                class="ml-2 text-xs text-g-400 line-through"
              >
                ¥{{ money(row.original_price) }}
              </span>
            </template>
          </ElTableColumn>
          <ElTableColumn label="建群/频道" width="140" align="center">
            <template #default="{ row }">
              <span>{{ row.benefits.max_owned_groups }} 群</span>
              <span class="text-g-400"> / </span>
              <span>{{ row.benefits.max_owned_channels }} 频道</span>
            </template>
          </ElTableColumn>
          <ElTableColumn label="成员上限" width="150" align="center">
            <template #default="{ row }">
              <span
                >{{ row.benefits.max_group_members }} / {{ row.benefits.max_channel_members }}</span
              >
            </template>
          </ElTableColumn>
          <ElTableColumn prop="description" label="说明" min-width="180" show-overflow-tooltip />
          <ElTableColumn label="状态" width="90" align="center">
            <template #default="{ row }">
              <ElTag :type="row.enabled ? 'success' : 'info'" size="small">
                {{ row.enabled ? '启用' : '停用' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="操作" width="130" fixed="right" align="center">
            <template #default="{ row }">
              <ElButton
                type="primary"
                link
                size="small"
                @click="openPlanDialog(row)"
                :disabled="isDemoAdmin"
              >
                编辑
              </ElButton>
            </template>
          </ElTableColumn>
        </ElTable>
      </ElTabPane>

      <ElTabPane label="会员用户" name="users">
        <div
          class="mb-4 flex items-center justify-between gap-3 max-md:flex-col max-md:items-stretch"
        >
          <div class="flex items-center gap-2 max-md:flex-col max-md:items-stretch">
            <ElInput
              v-model="userQuery.keyword"
              placeholder="搜索用户/手机号"
              clearable
              style="width: 240px"
              @keyup.enter="loadUsers"
            />
            <ElSelect v-model="userQuery.level" clearable placeholder="等级" style="width: 120px">
              <ElOption label="普通" value="0" />
              <ElOption label="VIP" value="1" />
              <ElOption label="SVIP" value="2" />
            </ElSelect>
            <ElSelect v-model="userQuery.status" clearable placeholder="状态" style="width: 130px">
              <ElOption label="未开通" value="none" />
              <ElOption label="有效" value="active" />
              <ElOption label="已冻结" value="frozen" />
              <ElOption label="已过期" value="expired" />
              <ElOption label="已取消" value="canceled" />
            </ElSelect>
            <ElButton type="primary" @click="loadUsers">搜索</ElButton>
            <ElButton @click="resetUsers">重置</ElButton>
          </div>
          <ElButton @click="loadUsers" :loading="userLoading">
            <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
            刷新
          </ElButton>
        </div>

        <ElTable :data="users" v-loading="userLoading" stripe border>
          <ElTableColumn label="用户" min-width="220">
            <template #default="{ row }">
              <div class="flex items-center gap-3">
                <ElAvatar :size="36" :src="fixImageUrl(row.avatar)">
                  {{ (row.nickname || row.username || 'U').charAt(0) }}
                </ElAvatar>
                <div>
                  <div class="font-medium">{{ row.nickname || row.username }}</div>
                  <div class="text-xs text-g-400">@{{ row.username }} · {{ row.uuid }}</div>
                </div>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="会员" width="140" align="center">
            <template #default="{ row }">
              <span v-if="row.level > 0" :class="['vip-badge', row.level >= 2 ? 'svip' : 'vip']">
                {{ row.level_name }}
              </span>
              <ElTag v-else size="small" type="info">普通</ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="套餐" min-width="160" show-overflow-tooltip>
            <template #default="{ row }">{{ row.plan_name || '-' }}</template>
          </ElTableColumn>
          <ElTableColumn label="到期时间" width="180" align="center">
            <template #default="{ row }">{{ formatTime(row.expired_at) }}</template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="100" align="center">
            <template #default="{ row }">
              <ElTag :type="userStatusTagType(row)" size="small">
                {{ userStatusText(row) }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="操作" width="230" fixed="right" align="center">
            <template #default="{ row }">
              <ElButton
                type="primary"
                link
                size="small"
                @click="openGrantDialog(row)"
                :disabled="isDemoAdmin"
              >
                开通/续期
              </ElButton>
              <ElButton
                v-if="row.vip_status === 'frozen'"
                type="success"
                link
                size="small"
                @click="unfreezeUserVip(row)"
                :disabled="isDemoAdmin"
              >
                解冻
              </ElButton>
              <ElButton
                v-else
                type="warning"
                link
                size="small"
                @click="freezeUserVip(row)"
                :disabled="
                  isDemoAdmin ||
                  !row.vip_status ||
                  row.vip_status === 'expired' ||
                  row.vip_status === 'canceled'
                "
              >
                冻结
              </ElButton>
              <ElButton
                type="danger"
                link
                size="small"
                @click="cancelUserVip(row)"
                :disabled="isDemoAdmin || !row.vip_status"
              >
                取消
              </ElButton>
            </template>
          </ElTableColumn>
        </ElTable>

        <div class="mt-4 flex justify-end">
          <ElPagination
            v-model:current-page="userQuery.page"
            v-model:page-size="userQuery.page_size"
            :total="userTotal"
            :page-sizes="[10, 20, 50, 100]"
            layout="total, sizes, prev, pager, next, jumper"
            @size-change="loadUsers"
            @current-change="loadUsers"
          />
        </div>
      </ElTabPane>

      <ElTabPane label="订单记录" name="orders">
        <div
          class="mb-4 flex items-center justify-between gap-3 max-md:flex-col max-md:items-stretch"
        >
          <div class="flex items-center gap-2 max-md:flex-col max-md:items-stretch">
            <ElInput
              v-model="orderQuery.keyword"
              placeholder="搜索订单/用户"
              clearable
              style="width: 240px"
              @keyup.enter="loadOrders"
            />
            <ElSelect
              v-model="orderQuery.status"
              clearable
              placeholder="订单状态"
              style="width: 130px"
            >
              <ElOption label="待支付" value="pending" />
              <ElOption label="已支付" value="paid" />
              <ElOption label="已取消" value="canceled" />
              <ElOption label="已退款" value="refunded" />
            </ElSelect>
            <ElButton type="primary" @click="loadOrders">搜索</ElButton>
            <ElButton @click="resetOrders">重置</ElButton>
          </div>
          <ElButton @click="loadOrders" :loading="orderLoading">
            <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
            刷新
          </ElButton>
        </div>

        <ElTable :data="orders" v-loading="orderLoading" stripe border>
          <ElTableColumn prop="order_no" label="订单号" min-width="190" show-overflow-tooltip />
          <ElTableColumn label="用户" min-width="170">
            <template #default="{ row }">
              <div class="font-medium">{{ row.nickname || row.username }}</div>
              <div class="text-xs text-g-400">@{{ row.username }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="套餐" min-width="150">
            <template #default="{ row }">
              <span>{{ row.plan_name }}</span>
              <span :class="['vip-badge', row.plan_level >= 2 ? 'svip' : 'vip']">
                {{ row.plan_level >= 2 ? 'SVIP' : 'VIP' }}
              </span>
            </template>
          </ElTableColumn>
          <ElTableColumn label="金额" width="110" align="right">
            <template #default="{ row }">¥{{ money(row.amount) }}</template>
          </ElTableColumn>
          <ElTableColumn label="方式" width="100" align="center">
            <template #default="{ row }">{{ payMethodText(row.pay_method) }}</template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="100" align="center">
            <template #default="{ row }">
              <ElTag :type="row.status === 'paid' ? 'success' : 'info'" size="small">
                {{ orderStatusText(row.status) }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="创建时间" width="180" align="center">
            <template #default="{ row }">{{ formatTime(row.created_at) }}</template>
          </ElTableColumn>
        </ElTable>

        <div class="mt-4 flex justify-end">
          <ElPagination
            v-model:current-page="orderQuery.page"
            v-model:page-size="orderQuery.page_size"
            :total="orderTotal"
            :page-sizes="[10, 20, 50, 100]"
            layout="total, sizes, prev, pager, next, jumper"
            @size-change="loadOrders"
            @current-change="loadOrders"
          />
        </div>
      </ElTabPane>
    </ElTabs>

    <ElDialog
      v-model="planDialogVisible"
      :title="editingPlan ? '编辑套餐' : '新增套餐'"
      width="720px"
      destroy-on-close
    >
      <ElForm :model="planForm" label-width="120px">
        <ElFormItem label="套餐编码" required>
          <ElInput v-model="planForm.code" :disabled="!!editingPlan" placeholder="例如 vip_month" />
        </ElFormItem>
        <ElFormItem label="套餐名称" required>
          <ElInput v-model="planForm.name" placeholder="例如 VIP 月卡" />
        </ElFormItem>
        <ElFormItem label="会员等级" required>
          <ElRadioGroup v-model="planForm.level" @change="applyLevelDefaults">
            <ElRadioButton :value="1">VIP</ElRadioButton>
            <ElRadioButton :value="2">SVIP</ElRadioButton>
          </ElRadioGroup>
        </ElFormItem>
        <ElFormItem label="有效期" required>
          <ElInputNumber
            v-model="planForm.duration_days"
            :min="1"
            :max="3650"
            controls-position="right"
          />
          <span class="ml-2 text-xs text-g-400">天</span>
        </ElFormItem>
        <ElFormItem label="价格" required>
          <ElInputNumber
            v-model="planForm.price"
            :min="0"
            :precision="2"
            controls-position="right"
          />
          <span class="mx-3 text-g-400">原价</span>
          <ElInputNumber
            v-model="planForm.original_price"
            :min="0"
            :precision="2"
            controls-position="right"
          />
        </ElFormItem>
        <ElFormItem label="权益标识">
          <div class="vip-badge-editor">
            <div class="flex items-center gap-3">
              <ElInput v-model="planForm.benefits.badge" style="width: 160px" />
              <span :class="['vip-badge', planForm.level >= 2 ? 'svip' : 'vip']">
                <img
                  v-if="planForm.benefits.badge_icon"
                  :src="fixImageUrl(planForm.benefits.badge_icon)"
                  alt="vip"
                  class="vip-badge-inline-icon"
                />
                {{ planForm.benefits.badge }}
              </span>
            </div>
            <div class="mt-3 flex items-center gap-3">
              <ElUpload
                :action="vipBadgeUploadUrl"
                :headers="uploadHeaders"
                :show-file-list="false"
                accept="image/*"
                :disabled="isDemoAdmin"
                :on-success="handleBadgeIconUploadSuccess"
              >
                <button class="vip-badge-upload" type="button" :disabled="isDemoAdmin">
                  <img
                    v-if="planForm.benefits.badge_icon"
                    :src="fixImageUrl(planForm.benefits.badge_icon)"
                    alt="vip"
                    class="h-full w-full object-cover"
                  />
                  <ArtSvgIcon v-else icon="ri:image-add-line" class="text-g-400 text-lg" />
                </button>
              </ElUpload>
              <ElButton
                v-if="planForm.benefits.badge_icon"
                size="small"
                @click="clearBadgeIcon"
                :disabled="isDemoAdmin"
              >
                清除小图
              </ElButton>
              <span class="text-xs text-g-400">建议透明 PNG/WebP，大小不超过 2MB。</span>
            </div>
          </div>
        </ElFormItem>
        <ElDivider content-position="left">创建与人数</ElDivider>
        <ElFormItem label="可创建">
          <ElSwitch v-model="planForm.benefits.can_create_group" active-text="群聊" />
          <ElSwitch
            v-model="planForm.benefits.can_create_channel"
            active-text="频道"
            class="ml-5"
          />
        </ElFormItem>
        <ElFormItem label="数量上限">
          <ElInputNumber
            v-model="planForm.benefits.max_owned_groups"
            :min="0"
            controls-position="right"
          />
          <span class="mx-3 text-g-400">群</span>
          <ElInputNumber
            v-model="planForm.benefits.max_owned_channels"
            :min="0"
            controls-position="right"
          />
          <span class="ml-3 text-g-400">频道</span>
        </ElFormItem>
        <ElFormItem label="成员上限">
          <ElInputNumber
            v-model="planForm.benefits.max_group_members"
            :min="0"
            controls-position="right"
          />
          <span class="mx-3 text-g-400">群成员</span>
          <ElInputNumber
            v-model="planForm.benefits.max_channel_members"
            :min="0"
            controls-position="right"
          />
          <span class="ml-3 text-g-400">频道订阅</span>
        </ElFormItem>
        <ElDivider content-position="left">容量与高级能力</ElDivider>
        <ElFormItem label="上传上限">
          <div class="grid grid-cols-2 gap-3">
            <ElInputNumber
              v-model="planForm.benefits.upload_image_limit_mb"
              :min="1"
              controls-position="right"
            />
            <ElInputNumber
              v-model="planForm.benefits.upload_video_limit_mb"
              :min="1"
              controls-position="right"
            />
            <ElInputNumber
              v-model="planForm.benefits.upload_voice_limit_mb"
              :min="1"
              controls-position="right"
            />
            <ElInputNumber
              v-model="planForm.benefits.upload_file_limit_mb"
              :min="1"
              controls-position="right"
            />
          </div>
          <span class="ml-3 text-xs text-g-400">依次为图片、视频、语音、文件，单位 MB</span>
        </ElFormItem>
        <ElFormItem label="置顶会话">
          <ElInputNumber
            v-model="planForm.benefits.max_pinned_chats"
            :min="0"
            controls-position="right"
          />
        </ElFormItem>
        <ElFormItem label="高级能力">
          <ElSwitch v-model="planForm.benefits.can_set_public_username" active-text="公开用户名" />
          <ElSwitch
            v-model="planForm.benefits.can_enable_member_protection"
            active-text="成员保护"
            class="ml-5"
          />
        </ElFormItem>
        <ElFormItem label="说明">
          <ElInput
            v-model="planForm.description"
            type="textarea"
            :rows="2"
            maxlength="200"
            show-word-limit
          />
        </ElFormItem>
        <ElFormItem label="状态">
          <ElSwitch v-model="planForm.enabled" active-text="启用" inactive-text="停用" />
          <span class="mx-4 text-g-400">顺序</span>
          <ElInputNumber v-model="planForm.sort" :min="0" :max="9999" controls-position="right" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="planDialogVisible = false">取消</ElButton>
        <ElButton type="primary" @click="savePlan" :loading="planSaving">保存</ElButton>
      </template>
    </ElDialog>

    <ElDialog v-model="grantDialogVisible" title="开通/续期会员" width="480px" destroy-on-close>
      <ElForm :model="grantForm" label-width="100px">
        <ElFormItem label="用户">
          <span>{{ grantUser?.nickname || grantUser?.username }} @{{ grantUser?.username }}</span>
        </ElFormItem>
        <ElFormItem label="套餐" required>
          <ElSelect
            v-model="grantForm.plan_id"
            placeholder="选择套餐"
            class="w-full"
            @change="syncGrantDays"
          >
            <ElOption
              v-for="plan in plans"
              :key="plan.id"
              :label="`${plan.name} · ${plan.duration_days}天`"
              :value="plan.id"
            />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="天数">
          <ElInputNumber v-model="grantForm.days" :min="1" :max="3650" controls-position="right" />
        </ElFormItem>
        <ElFormItem label="备注">
          <ElInput v-model="grantForm.remark" placeholder="例如：线下开通、活动赠送" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="grantDialogVisible = false">取消</ElButton>
        <ElButton type="primary" @click="submitGrant" :loading="grantSaving">确认开通</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { usePermission } from '@/hooks/usePermission'
  import { useUserStore } from '@/store/modules/user'
  import { fixImageUrl } from '@/utils/url'
  import {
    cancelVip,
    createVipPlan,
    freezeVip,
    getVipOrders,
    getVipFreeEntitlements,
    getVipPlans,
    getVipUsers,
    grantVip,
    unfreezeVip,
    updateVipFreeEntitlements,
    updateVipPlan,
    type VipEntitlements,
    type VipOrderItem,
    type VipPlanItem,
    type VipPlanPayload,
    type VipUserItem
  } from '@/api/admin'

  const activeTab = ref('plans')
  const { isDemoAdmin } = usePermission()
  const userStore = useUserStore()

  const plans = ref<VipPlanItem[]>([])
  const users = ref<VipUserItem[]>([])
  const orders = ref<VipOrderItem[]>([])
  const planLoading = ref(false)
  const userLoading = ref(false)
  const orderLoading = ref(false)
  const freeLoading = ref(false)
  const planSaving = ref(false)
  const freeSaving = ref(false)
  const grantSaving = ref(false)
  const pageError = ref('')
  const planDialogVisible = ref(false)
  const grantDialogVisible = ref(false)
  const editingPlan = ref<VipPlanItem | null>(null)
  const grantUser = ref<VipUserItem | null>(null)
  const userTotal = ref(0)
  const orderTotal = ref(0)
  const enabledPlanCount = computed(() => plans.value.filter((item) => item.enabled).length)
  const activeVipUserCount = computed(() => users.value.filter((item) => item.is_active).length)
  const activeSvipUserCount = computed(
    () => users.value.filter((item) => item.is_active && item.level >= 2).length
  )
  const frozenVipUserCount = computed(
    () => users.value.filter((item) => item.vip_status === 'frozen').length
  )
  const vipBadgeUploadUrl = computed(
    () =>
      `${(import.meta.env.VITE_API_URL || '/api/v1').replace(/\/$/, '')}/admin/vip/badge-icon`
  )
  const uploadHeaders = computed(() => ({
    Authorization: `Bearer ${userStore.accessToken}`
  }))

  const userQuery = reactive({
    page: 1,
    page_size: 20,
    keyword: '',
    level: '',
    status: ''
  })
  const orderQuery = reactive({
    page: 1,
    page_size: 20,
    keyword: '',
    status: ''
  })

  function defaultBenefits(level = 1): VipEntitlements {
    if (level <= 0) {
      return {
        can_create_group: true,
        can_create_channel: false,
        max_owned_groups: 3,
        max_owned_channels: 0,
        max_group_members: 100,
        max_channel_members: 0,
        max_pinned_chats: 5,
        upload_image_limit_mb: 10,
        upload_video_limit_mb: 100,
        upload_voice_limit_mb: 20,
        upload_file_limit_mb: 100,
        can_set_public_username: false,
        can_enable_member_protection: false,
        badge: '',
        badge_icon: ''
      }
    }
    if (level >= 2) {
      return {
        can_create_group: true,
        can_create_channel: true,
        max_owned_groups: 20,
        max_owned_channels: 10,
        max_group_members: 1000,
        max_channel_members: 5000,
        max_pinned_chats: 20,
        upload_image_limit_mb: 50,
        upload_video_limit_mb: 1024,
        upload_voice_limit_mb: 100,
        upload_file_limit_mb: 2048,
        can_set_public_username: true,
        can_enable_member_protection: true,
        badge: 'SVIP',
        badge_icon: ''
      }
    }
    return {
      can_create_group: true,
      can_create_channel: false,
      max_owned_groups: 5,
      max_owned_channels: 0,
      max_group_members: 500,
      max_channel_members: 0,
      max_pinned_chats: 10,
      upload_image_limit_mb: 20,
      upload_video_limit_mb: 300,
      upload_voice_limit_mb: 50,
      upload_file_limit_mb: 500,
      can_set_public_username: false,
      can_enable_member_protection: false,
      badge: 'VIP',
      badge_icon: ''
    }
  }

  const planForm = reactive<VipPlanPayload>({
    code: '',
    name: '',
    level: 1,
    duration_days: 30,
    price: 0,
    original_price: 0,
    benefits: defaultBenefits(1),
    description: '',
    sort: 0,
    enabled: true
  })
  const grantForm = reactive({
    plan_id: 0,
    days: 30,
    remark: ''
  })
  const freeBenefits = reactive<VipEntitlements>(defaultBenefits(0))

  function resetPlanForm(plan?: VipPlanItem) {
    editingPlan.value = plan || null
    const source = plan
      ? {
          code: plan.code,
          name: plan.name,
          level: plan.level,
          duration_days: plan.duration_days,
          price: plan.price,
          original_price: plan.original_price,
          benefits: { ...defaultBenefits(plan.level), ...plan.benefits },
          description: plan.description,
          sort: plan.sort,
          enabled: plan.enabled
        }
      : {
          code: '',
          name: '',
          level: 1,
          duration_days: 30,
          price: 18,
          original_price: 30,
          benefits: defaultBenefits(1),
          description: '',
          sort: 0,
          enabled: true
        }
    Object.assign(planForm, source)
  }

  function applyLevelDefaults() {
    const badgeIcon = planForm.benefits.badge_icon || ''
    planForm.benefits = defaultBenefits(planForm.level)
    if (!planForm.benefits.badge) planForm.benefits.badge = planForm.level >= 2 ? 'SVIP' : 'VIP'
    planForm.benefits.badge_icon = badgeIcon
  }

  function handleBadgeIconUploadSuccess(res: any) {
    const url = res?.data?.url || res?.url || ''
    if (url) {
      planForm.benefits.badge_icon = url
      ElMessage.success('会员小图上传成功')
    } else {
      ElMessage.error('会员小图上传失败')
    }
  }

  function clearBadgeIcon() {
    planForm.benefits.badge_icon = ''
  }

  function openPlanDialog(plan?: VipPlanItem) {
    resetPlanForm(plan)
    planDialogVisible.value = true
  }

  async function savePlan() {
    if (!planForm.code?.trim() || !planForm.name.trim()) {
      ElMessage.warning('请填写套餐编码和名称')
      return
    }
    planSaving.value = true
    try {
      const payload = { ...planForm, benefits: { ...planForm.benefits } }
      if (editingPlan.value) {
        await updateVipPlan(editingPlan.value.id, payload)
      } else {
        await createVipPlan(payload)
      }
      ElMessage.success('保存成功')
      planDialogVisible.value = false
      pageError.value = ''
      await loadPlans()
    } catch (error) {
      showPageError('保存会员套餐失败', error)
    } finally {
      planSaving.value = false
    }
  }

  async function loadPlans() {
    planLoading.value = true
    try {
      plans.value = await getVipPlans()
      pageError.value = ''
    } catch (error) {
      showPageError('会员套餐加载失败', error)
    } finally {
      planLoading.value = false
    }
  }

  async function loadFreeEntitlements() {
    freeLoading.value = true
    try {
      const res = await getVipFreeEntitlements()
      Object.assign(freeBenefits, { ...defaultBenefits(0), ...res })
      pageError.value = ''
    } catch (error) {
      showPageError('普通用户额度加载失败', error)
    } finally {
      freeLoading.value = false
    }
  }

  async function saveFreeEntitlements() {
    freeSaving.value = true
    try {
      const payload = { ...freeBenefits }
      const res = await updateVipFreeEntitlements(payload)
      Object.assign(freeBenefits, { ...defaultBenefits(0), ...res })
      ElMessage.success('普通用户额度已保存')
      pageError.value = ''
    } catch (error) {
      showPageError('保存普通用户额度失败', error)
    } finally {
      freeSaving.value = false
    }
  }

  async function loadUsers() {
    userLoading.value = true
    try {
      const res = await getVipUsers(userQuery)
      users.value = res.list
      userTotal.value = res.total
      pageError.value = ''
    } catch (error) {
      showPageError('会员用户加载失败', error)
    } finally {
      userLoading.value = false
    }
  }

  function resetUsers() {
    Object.assign(userQuery, { page: 1, page_size: 20, keyword: '', level: '', status: '' })
    loadUsers()
  }

  async function loadOrders() {
    orderLoading.value = true
    try {
      const res = await getVipOrders(orderQuery)
      orders.value = res.list
      orderTotal.value = res.total
      pageError.value = ''
    } catch (error) {
      showPageError('会员订单加载失败', error)
    } finally {
      orderLoading.value = false
    }
  }

  function resetOrders() {
    Object.assign(orderQuery, { page: 1, page_size: 20, keyword: '', status: '' })
    loadOrders()
  }

  function openGrantDialog(user: VipUserItem) {
    grantUser.value = user
    const firstPlan = plans.value[0]
    grantForm.plan_id = user.plan_id || firstPlan?.id || 0
    grantForm.days = firstPlan?.duration_days || 30
    grantForm.remark = ''
    syncGrantDays()
    grantDialogVisible.value = true
  }

  function syncGrantDays() {
    const plan = plans.value.find((item) => item.id === grantForm.plan_id)
    if (plan) grantForm.days = plan.duration_days
  }

  async function submitGrant() {
    if (!grantUser.value || !grantForm.plan_id) {
      ElMessage.warning('请选择会员套餐')
      return
    }
    grantSaving.value = true
    try {
      await grantVip(grantUser.value.id, grantForm.plan_id, grantForm.days, grantForm.remark)
      ElMessage.success('会员已开通')
      grantDialogVisible.value = false
      pageError.value = ''
      await loadUsers()
    } catch (error) {
      showPageError('开通会员失败', error)
    } finally {
      grantSaving.value = false
    }
  }

  async function cancelUserVip(user: VipUserItem) {
    try {
      await ElMessageBox.confirm(
        `确定取消 ${user.nickname || user.username} 的会员？`,
        '取消会员',
        {
          type: 'warning'
        }
      )
    } catch {
      return
    }
    try {
      await cancelVip(user.id, '后台取消会员')
      ElMessage.success('已取消会员')
      pageError.value = ''
      await loadUsers()
    } catch (error) {
      showPageError('取消会员失败', error)
    }
  }

  async function freezeUserVip(user: VipUserItem) {
    try {
      await ElMessageBox.confirm(
        `确定冻结 ${user.nickname || user.username} 的会员权益？`,
        '冻结会员',
        {
          type: 'warning'
        }
      )
    } catch {
      return
    }
    try {
      await freezeVip(user.id, '后台冻结会员')
      ElMessage.success('已冻结会员')
      pageError.value = ''
      await loadUsers()
    } catch (error) {
      showPageError('冻结会员失败', error)
    }
  }

  async function unfreezeUserVip(user: VipUserItem) {
    try {
      await ElMessageBox.confirm(
        `确定恢复 ${user.nickname || user.username} 的会员权益？`,
        '解冻会员',
        {
          type: 'warning'
        }
      )
    } catch {
      return
    }
    try {
      await unfreezeVip(user.id, '后台解冻会员')
      ElMessage.success('已解冻会员')
      pageError.value = ''
      await loadUsers()
    } catch (error) {
      showPageError('解冻会员失败', error)
    }
  }

  function showPageError(message: string, error: unknown) {
    pageError.value = message
    ElMessage.error(message)
    console.error('[VIP Admin]', message, error)
  }

  function money(value?: number) {
    return Number(value || 0).toFixed(2)
  }

  function formatTime(value?: string | null) {
    if (!value) return '-'
    return new Date(value).toLocaleString('zh-CN', { hour12: false })
  }

  function userStatusText(row: VipUserItem) {
    if (!row.vip_status) return '未开通'
    if (row.is_active) return '有效'
    if (row.vip_status === 'expired') return '已过期'
    if (row.vip_status === 'canceled') return '已取消'
    if (row.vip_status === 'frozen') return '已冻结'
    return row.vip_status
  }

  function userStatusTagType(row: VipUserItem) {
    if (row.is_active) return 'success'
    if (!row.vip_status) return 'warning'
    if (row.vip_status === 'frozen') return 'danger'
    return 'info'
  }

  function orderStatusText(status: string) {
    const map: Record<string, string> = {
      pending: '待支付',
      paid: '已支付',
      canceled: '已取消',
      failed: '失败',
      refunded: '已退款'
    }
    return map[status] || status
  }

  function payMethodText(method: string) {
    const map: Record<string, string> = {
      wallet: '钱包',
      manual: '后台'
    }
    return map[method] || method
  }

  onMounted(async () => {
    await Promise.all([loadFreeEntitlements(), loadPlans()])
    await Promise.all([loadUsers(), loadOrders()])
  })
</script>

<style scoped lang="scss">
  .vip-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 42px;
    height: 20px;
    padding: 0 8px;
    margin-left: 6px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 700;
    line-height: 20px;
    letter-spacing: 0;

    &.vip {
      color: #f7fbff;
      background: linear-gradient(135deg, #2f80ed, #7b61ff);
      box-shadow: 0 3px 8px rgb(47 128 237 / 18%);
    }

    &.svip {
      color: #2f1d08;
      background: linear-gradient(135deg, #ffe1a1, #f5b841);
      box-shadow: 0 3px 8px rgb(245 184 65 / 20%);
    }
  }

  .vip-badge-inline-icon {
    width: 13px;
    height: 13px;
    margin-right: 4px;
    border-radius: 999px;
    object-fit: cover;
  }

  .vip-badge-editor {
    width: 100%;
  }

  .vip-badge-upload {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    padding: 0;
    overflow: hidden;
    cursor: pointer;
    background: var(--el-fill-color-light);
    border: 1px dashed var(--el-border-color);
    border-radius: 8px;

    &:disabled {
      cursor: not-allowed;
      opacity: 0.55;
    }
  }

  .vip-overview {
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 12px;

    @media (max-width: 960px) {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  .vip-stat-card {
    padding: 14px 16px;
    border: 1px solid rgb(0 0 0 / 6%);
    border-radius: 8px;
    background: var(--el-bg-color);
  }

  .vip-stat-label {
    color: var(--el-text-color-secondary);
    font-size: 13px;
  }

  .vip-stat-value {
    margin-top: 6px;
    color: var(--el-text-color-primary);
    font-size: 22px;
    font-weight: 700;
    line-height: 1.2;
  }
</style>
