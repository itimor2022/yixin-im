<template>
  <ElDialog v-model="dialogVisible" :title="'编辑用户'" width="480px" align-center>
    <ElForm ref="formRef" :model="formData" :rules="rules" label-width="80px">
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
  import { updateUser } from '@/api/system-manage'

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

  // 对话框显示控制
  const dialogVisible = computed({
    get: () => props.visible,
    set: (value) => emit('update:visible', value)
  })

  // 提交状态
  const submitting = ref(false)

  // 表单实例
  const formRef = ref<FormInstance>()

  // 表单数据
  const formData = reactive({
    nickname: '',
    username: '',
    phone: '',
    bio: '',
    status: 1
  })

  // 表单验证规则
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

  /**
   * 初始化表单数据
   */
  const initFormData = () => {
    const row = props.userData
    if (row) {
      Object.assign(formData, {
        nickname: row.nickname || row.userName || '',
        username: row.username || '',
        phone: row.phone || (row.userPhone !== '-' ? row.userPhone : '') || '',
        bio: row.bio || '',
        status: parseInt(row.status || '1')
      })
    }
  }

  /**
   * 监听对话框状态变化
   */
  watch(
    () => [props.visible, props.userData],
    ([visible]) => {
      if (visible) {
        initFormData()
        nextTick(() => {
          formRef.value?.clearValidate()
        })
      }
    },
    { immediate: true }
  )

  /**
   * 提交表单
   */
  const handleSubmit = async () => {
    if (!formRef.value) return

    await formRef.value.validate(async (valid) => {
      if (valid && props.userData?.id) {
        try {
          submitting.value = true
          await updateUser(props.userData.id, {
            nickname: formData.nickname,
            username: formData.username,
            phone: formData.phone || undefined,
            bio: formData.bio || undefined,
            status: formData.status
          } as any)
          ElMessage.success('更新成功')
          dialogVisible.value = false
          emit('submit')
        } catch (error) {
          console.error('更新失败:', error)
        } finally {
          submitting.value = false
        }
      }
    })
  }
</script>
