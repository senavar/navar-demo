<script setup>
import { ref, watch, computed, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Cropper } from 'vue-advanced-cropper'
import 'vue-advanced-cropper/dist/style.css'

// --- COMPONENT SETUP ---

const { t, locale } = useI18n()
const emit = defineEmits(['birthdayAdded'])

// --- REACTIVE STATE ---

const newPerson = ref({ name: '', year: null, month: null, day: null })
const profilePictureFile = ref(null)
const profilePicturePreview = ref(null)
const isSubmitting = ref(false)
const apiError = ref(null)
const validationError = ref(null)
const fileError = ref(null)

// Cropper-specific state
const showCropper = ref(false)
const cropperImageSrc = ref(null)
const originalImageSrc = ref(null)
const cropperRef = ref(null)

// --- COMPUTED PROPERTIES ---

const months = computed(() => {
  return Array.from({ length: 12 }, (e, i) => {
    const monthName = new Date(2023, i, 1).toLocaleString(locale.value, { month: 'long' })
    return {
      value: i + 1,
      name: monthName.charAt(0).toUpperCase() + monthName.slice(1)
    }
  })
})

// --- LOGIC AND VALIDATION ---

function handleFileChange(event) {
  const file = event.target.files[0]
  if (!file) return

  const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg']
  if (!allowedTypes.includes(file.type)) {
    fileError.value = t('errorInvalidFileType')
    return
  }
  const maxSizeInBytes = 5 * 1024 * 1024
  if (file.size > maxSizeInBytes) {
    fileError.value = t('errorFileTooLarge', { size: '5MB' })
    return
  }

  fileError.value = null
  const reader = new FileReader()
  reader.onload = (e) => {
    originalImageSrc.value = e.target.result
    cropperImageSrc.value = originalImageSrc.value
    showCropper.value = true
  }
  reader.readAsDataURL(file)
  event.target.value = ''
}

function editImage() {
  if (!originalImageSrc.value) return
  cropperImageSrc.value = originalImageSrc.value
  showCropper.value = true
}

function onCrop() {
  if (!cropperRef.value) return
  const { canvas } = cropperRef.value.getResult()
  if (canvas) {
    profilePicturePreview.value = canvas.toDataURL()
    canvas.toBlob(blob => {
      profilePictureFile.value = blob
    }, 'image/jpeg')
  }
  closeCropper()
}

function closeCropper() {
  showCropper.value = false
}

function cleanupImageData() {
  // This function is key for memory management
  profilePictureFile.value = null
  profilePicturePreview.value = null
  originalImageSrc.value = null
  cropperImageSrc.value = null
}

function resetForm() {
  newPerson.value = { name: '', year: null, month: null, day: null }
  apiError.value = null
  validationError.value = null
  fileError.value = null
  cleanupImageData()
  const fileInput = document.querySelector('#profile-picture')
  if (fileInput) {
    fileInput.value = ''
  }
}

watch(
  [() => newPerson.value.year, () => newPerson.value.month, () => newPerson.value.day],
  ([year, month, day]) => {
    if (!year || !month || !day) {
      validationError.value = null
      return
    }
    const date = new Date(year, month - 1, day)
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
      const monthName = new Date(year, month - 1).toLocaleString(locale.value, { month: 'long' })
      const daysInMonth = new Date(year, month, 0).getDate()
      validationError.value = t('errorInvalidDayInMonth', { monthName, year, daysInMonth })
    } else {
      validationError.value = null
    }
  }
)

async function addBirthday() {
  if (validationError.value || fileError.value) return
  isSubmitting.value = true
  apiError.value = null
  const formData = new FormData()
  formData.append('name', newPerson.value.name)
  formData.append('year', newPerson.value.year)
  formData.append('month', newPerson.value.month)
  formData.append('day', newPerson.value.day)
  if (profilePictureFile.value) {
    formData.append('profile_picture', profilePictureFile.value, 'profile.jpg')
  }
  try {
    const response = await fetch('/api/birthdays', {
      method: 'POST',
      body: formData
    })
    if (!response.ok) {
      let friendly = 'Failed to add birthday.'
      try {
        const errorData = await response.json()
        if (errorData && Array.isArray(errorData.errors) && errorData.errors.length) {
            friendly = errorData.errors.join('; ')
        } else if (errorData && errorData.message) {
            friendly = errorData.message
        }
      } catch (e) {
        // swallow JSON parse errors
      }
      throw new Error(friendly)
    }
    emit('birthdayAdded')
    resetForm()
  } catch (e) {
    apiError.value = e.message
  } finally {
    isSubmitting.value = false
  }
}

// Lifecycle hook to clean up when the form is hidden/unmounted
onUnmounted(() => {
  cleanupImageData()
})
</script>

<template>
  <div class="form-container">
    <h2>{{ $t('addBirthdayTitle') }}</h2>
    <form @submit.prevent="addBirthday" novalidate>
      <input
        v-model="newPerson.name"
        :placeholder="$t('namePlaceholder')"
        type="text"
        required
        class="full-width"
      />
      <div class="date-inputs">
        <select v-model.number="newPerson.month" :class="{ invalid: validationError }" required>
          <option :value="null" disabled>{{ $t('monthPlaceholder') }}</option>
          <option v-for="month in months" :key="month.value" :value="month.value">
            {{ month.name }}
          </option>
        </select>
        <input
          v-model.number="newPerson.day"
          :placeholder="$t('dayPlaceholder')"
          :class="{ invalid: validationError }"
          type="number"
          min="1"
          max="31"
          required
        />
        <input
          v-model.number="newPerson.year"
          :placeholder="$t('yearPlaceholder')"
          :class="{ invalid: validationError }"
          type="number"
          required
        />
      </div>
      <p v-if="validationError" class="error-message">{{ validationError }}</p>
      <div class="file-input-wrapper full-width">
        <input
          id="profile-picture"
          type="file"
          accept="image/png, image/jpeg, image/jpg"
          @change="handleFileChange"
          class="file-input-hidden"
        />
        <div class="image-controls">
          <label for="profile-picture" class="file-input-button">
            {{ profilePicturePreview ? $t('changePicture') : $t('profilePictureLabel') }}
          </label>
          <div v-if="profilePicturePreview" class="image-preview-container" @click="editImage">
            <img :src="profilePicturePreview" class="preview-image" />
            <div class="edit-overlay">
              <span>{{ $t('editPicture') }}</span>
            </div>
          </div>
        </div>
      </div>
      <p v-if="fileError" class="error-message">{{ fileError }}</p>
      <button :disabled="isSubmitting || validationError || fileError" type="submit" class="full-width">
        {{ isSubmitting ? $t('addingButton') : $t('addButton') }}
      </button>
      <p v-if="apiError" class="error-message">{{ apiError }}</p>
    </form>
    <div v-if="showCropper" class="cropper-modal-overlay">
      <div class="cropper-modal-content">
        <h3>{{ $t('cropImageTitle') }}</h3>
        <cropper
          ref="cropperRef"
          :src="cropperImageSrc"
          :stencil-props="{ aspectRatio: 1/1 }"
          class="cropper-component"
        />
        <div class="cropper-actions">
          <button @click="closeCropper" type="button" class="button-secondary">{{ $t('cancel') }}</button>
          <button @click="onCrop" type="button">{{ $t('confirmCrop') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.form-container {
  margin-top: 2rem;
  padding-top: 2rem;
  border-top: 1px solid #e2e8f0;
}
h2 {
  border-bottom: 1px solid #ddd;
  padding-bottom: 0.5rem;
  color: #2d3748;
}
form {
  margin-top: 1rem;
  display: grid;
  gap: 1rem;
}
.date-inputs {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.75rem;
}
input, select {
  padding: 0.75rem;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 1em;
  background-color: white;
}
input.invalid, select.invalid {
  border-color: #d93025;
  box-shadow: 0 0 0 1px #d93025;
}
.full-width {
  grid-column: 1 / -1;
}
.file-input-wrapper {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1rem;
}
.image-controls {
  display: flex;
  align-items: center;
  gap: 1rem;
}
.file-input-hidden {
  display: none;
}
.file-input-button {
  display: inline-block;
  padding: 0.75rem 1.5rem;
  background-color: #6c757d;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1em;
  text-align: center;
  transition: background-color 0.2s;
}
.file-input-button:hover {
  background-color: #5a6268;
}
.image-preview-container {
  position: relative;
  cursor: pointer;
  width: 80px;
  height: 80px;
  border-radius: 50%;
  overflow: hidden;
  border: 2px solid #ddd;
}
.preview-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  transition: filter 0.2s ease-in-out;
}
.edit-overlay {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: linear-gradient(to top, rgba(0, 0, 0, 0.7) 0%, transparent 40%);
  color: white;
  display: flex;
  justify-content: center;
  align-items: flex-end;
  font-weight: bold;
  font-size: 0.2em;
  opacity: 1;
  transition: all 0.2s ease-in-out;
  padding-bottom: 8px;
  box-sizing: border-box;
}
.edit-overlay span {
  transition: transform 0.2s ease-in-out;
}
.image-preview-container:hover .edit-overlay {
  background: linear-gradient(to top, rgba(0, 0, 0, 0.8) 0%, transparent 50%);
}
.image-preview-container:hover .edit-overlay span {
  transform: translateY(-2px);
}
.image-preview-container:hover .preview-image {
  filter: brightness(0.7);
}
button {
  padding: 0.75rem;
  background-color: #007bff;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1em;
  transition: background-color 0.2s;
}
button:hover:not(:disabled) {
  background-color: #0056b3;
}
button:disabled {
  background-color: #a0a0a0;
  cursor: not-allowed;
}
.error-message {
  color: #d93025;
  grid-column: 1 / -1;
  text-align: center;
  margin: 0;
  font-size: 0.9em;
}
.cropper-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(0, 0, 0, 0.6);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
}
.cropper-modal-content {
  background-color: white;
  padding: 2rem;
  border-radius: 8px;
  box-shadow: 0 5px 15px rgba(0,0,0,0.3);
  width: 90vw;
  max-width: 500px;
  display: flex;
  flex-direction: column;
}
.cropper-modal-content h3 {
  margin-top: 0;
  margin-bottom: 1.5rem;
  text-align: center;
}
.cropper-component {
  height: 300px;
  width: 100%;
  background: #f0f0f0;
}
.cropper-actions {
  display: flex;
  justify-content: flex-end;
  gap: 1rem;
  margin-top: 1.5rem;
  flex-shrink: 0;
}
.button-secondary {
  background-color: #6c757d;
}
.button-secondary:hover {
  background-color: #5a6268;
}
</style>