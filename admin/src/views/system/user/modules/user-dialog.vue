<template>
  <ElDialog v-model="dialogVisible" :title="'编辑用户'" width="520px" align-center>
    <ElTabs v-model="activeTab">
      <!-- ── Tab 1: 基本信息 ── -->
      <ElTabPane label="基本信息" name="basic">
        <ElForm ref="formRef" :model="formData" :rules="rules" label-width="80px" class="pt-2">
          <ElFormItem label="昵称" prop="nickname">
            <ElInput v-model="formData.nickname" placeholder="请输入昵称" />
          </ElFormItem>
          <ElFormItem label="用户名" prop="username">
            <ElInput v-model="formData.username" placeholder="请输入用户名" />
          </ElFormItem>
          <ElFormItem label="手机号" prop="phone">
            <ElInput v-model="formData.phone" placeholder="请输入手机号" />
          </ElFormItem>
          <ElFormItem label="简介" prop="bio">
            <ElInput v-model="formData.bio" type="textarea" :rows="3" placeholder="请输入用户简介" />
          </ElFormItem>
          <ElFormItem label="状态" prop="status">
            <ElSelect v-model="formData.status" style="width: 100%">
              <ElOption label="正常" :value="1" />
              <ElOption label="禁用" :value="0" />
              <ElOption label="待审核" :value="2" />
            </ElSelect>
          </ElFormItem>
        </ElForm>
      </ElTabPane>

      <!-- ── Tab 2: 会员设置 ── -->
      <ElTabPane label="会员设置" name="member">
        <div class="pt-4 px-2">
          <!-- 会员开关 -->
          <div class="flex items-center justify-between mb-6 p-4 rounded-lg bg-gray-50">
            <div>
              <p class="font-semibold text-g-800">会员状态</p>
              <p class="text-xs text-g-400 mt-0.5">开启后用户将显示会员徽章</p>
            </div>
            <ElSwitch
              v-model="memberData.isMember"
              active-color="#3390EC"
              size="large"
            />
          </div>

          <!-- 徽章预览 -->
          <div class="mb-5">
            <p class="text-sm text-g-600 mb-2 font-medium">徽章预览</p>
            <div class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 bg-white">
              <span class="text-g-500 text-sm">用户昵称</span>
              <span
                v-if="memberData.isMember && memberData.badgeText"
                class="px-2 py-0.5 rounded text-white text-xs font-bold"
                :style="{ backgroundColor: memberData.badgeColor || '#3390EC' }"
              >
                {{ memberData.badgeText }}
              </span>
              <span v-else class="text-xs text-g-300">（暂无徽章）</span>
            </div>
          </div>

          <!-- 徽章文字 -->
          <div class="mb-4">
            <p class="text-sm text-g-600 mb-2 font-medium">徽章文字</p>
            <ElInput
              v-model="memberData.badgeText"
              placeholder="如：PREMIUM / VIP / 会员"
              maxlength="10"
              show-word-limit
              :disabled="!memberData.isMember"
            />
          </div>

          <!-- 徽章颜色 -->
          <div class="mb-4">
            <p class="text-sm text-g-600 mb-2 font-medium">徽章颜色</p>
            <div class="flex items-center gap-3">
              <ElColorPicker
                v-model="memberData.badgeColor"
                :disabled="!memberData.isMember"
                show-alpha
              />
              <ElInput
                v-model="memberData.badgeColor"
                placeholder="#3390EC"
                style="width: 140px"
                :disabled="!memberData.isMember"
              />
              <!-- 快选色板 -->
              <div class="flex gap-1.5">
                <span
                  v-for="c in presetColors"
                  :key="c"
                  class="size-6 rounded cursor-pointer border-2 transition-all"
                  :style="{ backgroundColor: c, borderColor: memberData.badgeColor === c ? '#333' : 'transparent' }"
                  @click="memberData.badgeColor = c"
                />
              </div>
            </div>
          </div>
        </div>
      </ElTabPane>
    </ElTabs>

    <template #footer>
      <div class="dialog-footer">
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="submitting" @click="handleSubmit">保存</ElButton>
      </div>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import type { FormInstance, FormRules } from 'element-plus'
  import { updateUser, setMembership } from '@/api/system-manage'

  interface UserData {
    id?: number
    userName?: string
    username?: string
    nickname?: string
    phone?: string
    bio?: string
    userPhone?: string
    status?: string
    uuid?: string
    isMember?: boolean
    badgeText?: string
    badgeColor?: string
  }

  interface Props {
    visible: boolean
    type: string
    userData?: Partial<UserData>
  }

  interface Emits {
    (e: 'update:visible', value: boolean): void
    (e: 'submit'): void
  }

  const props = defineProps<Props>()
  const emit = defineEmits<Emits>()

  const activeTab = ref('basic')
  const submitting = ref(false)
  const formRef = ref<FormInstance>()

  const presetColors = ['#3390EC', '#7C3AED', '#059669', '#DC2626', '#D97706', '#DB2777']

  const dialogVisible = computed({
    get: () => props.visible,
    set: (value) => emit('update:visible', value)
  })

  const formData = reactive({
    nickname: '',
    username: '',
    phone: '',
    bio: '',
    status: 1
  })

  const memberData = reactive({
    isMember: false,
    badgeText: '',
    badgeColor: '#3390EC'
  })

  const rules: FormRules = {
    nickname: [
      { required: true, message: '请输入昵称', trigger: 'blur' },
      { min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'blur' }
    ],
    username: [
      { required: true, message: '请输入用户名', trigger: 'blur' },
      { min: 2, max: 30, message: '长度在 2 到 30 个字符', trigger: 'blur' },
      { pattern: /^[a-zA-Z0-9_]+$/, message: '只能包含字母、数字和下划线', trigger: 'blur' }
    ],
    phone: [{ pattern: /^1[3-9]\d{9}$/, message: '请输入正确的手机号格式', trigger: 'blur' }]
  }

  const initFormData = () => {
    const row = props.userData
    if (!row) return
    Object.assign(formData, {
      nickname: row.nickname || row.userName || '',
      username: row.username || '',
      phone: row.phone || (row.userPhone !== '-' ? row.userPhone : '') || '',
      bio: row.bio || '',
      status: parseInt(row.status || '1')
    })
    Object.assign(memberData, {
      isMember: !!row.isMember,
      badgeText: row.badgeText || '',
      badgeColor: row.badgeColor || '#3390EC'
    })
  }

  watch(
    () => [props.visible, props.userData],
    ([visible]) => {
      if (visible) {
        activeTab.value = 'basic'
        initFormData()
        nextTick(() => formRef.value?.clearValidate())
      }
    },
    { immediate: true }
  )

  const handleSubmit = async () => {
    if (!formRef.value || !props.userData?.id) return

    await formRef.value.validate(async (valid) => {
      if (!valid) return
      submitting.value = true
      const errors: string[] = []

      // 保存基本信息
      try {
        await updateUser(props.userData!.id!, {
          nickname: formData.nickname,
          username: formData.username,
          phone: formData.phone || undefined,
          bio: formData.bio || undefined,
          status: formData.status
        } as any)
      } catch (e) {
        console.error('基本信息保存失败:', e)
        errors.push('基本信息')
      }

      // 保存会员信息（独立执行，不受基本信息影响）
      try {
        await setMembership(props.userData!.id!, {
          is_member: memberData.isMember,
          badge_text: memberData.badgeText,
          badge_color: memberData.badgeColor
        })
      } catch (e) {
        console.error('会员信息保存失败:', e)
        errors.push('会员设置')
      }

      submitting.value = false

      if (errors.length === 0) {
        ElMessage.success('更新成功')
        dialogVisible.value = false
        emit('submit')
      } else {
        ElMessage.error(`以下项目保存失败：${errors.join('、')}，请重试`)
      }
    })
  }
</script>
