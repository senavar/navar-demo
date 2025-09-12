<template>
  <div class="modal-overlay" @click.self="close">
    <div class="modal-content">
      <h3>{{ $t('admin.editTitle', { name: personData.name }) }}</h3>
      <form @submit.prevent="submitUpdate">
        <!-- Name Input -->
        <div class="form-group">
          <label for="name">{{ $t('namePlaceholder') }}</label>
          <input id="name" v-model="personData.name" type="text" required />
        </div>

        <!-- Date Inputs -->
        <div class="form-group date-inputs">
          <div>
            <label for="month">{{ $t('monthPlaceholder') }}</label>
            <select id="month" v-model.number="personData.month" required>
              <option v-for="month in months" :key="month.value" :value="month.value">
                {{ month.name }}
              </option>
            </select>
          </div>
          <div>
            <label for="day">{{ $t('dayPlaceholder') }}</label>
            <input id="day" v-model.number="personData.day" type="number" min="1" max="31" required />
          </div>
          <div>
            <label for="year">{{ $t('yearPlaceholder') }}</label>
            <input id="year" v-model.number="personData.year" type="number" required />
          </div>
        </div>

        <!-- NEW: Picture Management Section -->
        <div class="form-group">
          <label>{{ $t('admin.table.photo') }}</label>
          <div class="picture-management">
            <img :src="picturePreviewUrl || personData.profile_picture_url || defaultAvatar" class="avatar-preview" @error="onImageError" />
            <div class="picture-actions">
              <!-- Hidden file input, triggered by the button -->
              <input type="file" @change="handleFileChange" accept="image/png, image/jpeg" ref="fileInput" style="display: none;" />
              <button type="button" @click="triggerFileInput" class="button-secondary">{{ $t('admin.changePhoto') }}</button>
              <button type="button" @click="removePicture" v-if="personData.profile_picture_url || picturePreviewUrl" class="button-danger">{{ $t('admin.removePhoto') }}</button>
            </div>
          </div>
        </div>

        <p v-if="error" class="error-message">{{ error }}</p>
        <div class="modal-actions">
          <button type="button" @click="close" class="button-secondary">{{ $t('cancel') }}</button>
          <button type="submit" :disabled="isSubmitting">{{ isSubmitting ? $t('submitButton') : $t('submitButton') }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import defaultAvatar from '../assets/birthday.svg'; // Placeholder for a default avatar

const props = defineProps({
  person: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close', 'updated']);

const { t, locale } = useI18n();
const personData = ref({ ...props.person });
const isSubmitting = ref(false);
const error = ref(null);

// --- NEW: State for picture management ---
const fileInput = ref(null);
const newProfilePictureFile = ref(null);
const picturePreviewUrl = ref(null);
const pictureWasDeleted = ref(false);

const months = computed(() => {
  return Array.from({ length: 12 }, (e, i) => {
    const monthName = new Date(2023, i, 1).toLocaleString(locale.value, { month: 'long' });
    return {
      value: i + 1,
      name: monthName.charAt(0).toUpperCase() + monthName.slice(1),
    };
  });
});

const close = () => {
  emit('close');
};

// --- NEW: Methods for picture handling ---
const triggerFileInput = () => {
  fileInput.value.click();
};

const handleFileChange = (event) => {
  const file = event.target.files[0];
  if (!file) return;

  if (!['image/jpeg', 'image/png'].includes(file.type)) {
    error.value = t('errorInvalidFileType');
    return;
  }
  if (file.size > 5 * 1024 * 1024) { // 5MB limit
    error.value = t('errorFileTooLarge', { size: '5MB' });
    return;
  }

  newProfilePictureFile.value = file;
  picturePreviewUrl.value = URL.createObjectURL(file);
  pictureWasDeleted.value = false; // A new file selection overrides a previous deletion
  error.value = null;
};

const removePicture = () => {
  newProfilePictureFile.value = null;
  picturePreviewUrl.value = null; // Clear the new preview
  personData.value.profile_picture_url = null; // Clear the old preview visually
  pictureWasDeleted.value = true;
};

const onImageError = (event) => {
  event.target.src = defaultAvatar;
};

// --- MODIFIED: submitUpdate now uses FormData ---
const submitUpdate = async () => {
  isSubmitting.value = true;
  error.value = null;

  const formData = new FormData();
  formData.append('name', personData.value.name);
  formData.append('year', personData.value.year);
  formData.append('month', personData.value.month);
  formData.append('day', personData.value.day);

  if (newProfilePictureFile.value) {
    formData.append('profile_picture', newProfilePictureFile.value);
  } else if (pictureWasDeleted.value) {
    formData.append('delete_picture', 'true');
  }

  try {
    const response = await fetch(`/api/birthdays/${personData.value.id}`, {
      method: 'PUT',
      // NOTE: We DO NOT set the 'Content-Type' header.
      // The browser will automatically set it to 'multipart/form-data'
      // with the correct boundary when the body is a FormData object.
      body: formData,
    });

    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.message || 'Failed to update birthday.');
    }
    emit('updated');
  } catch (e) {
    error.value = e.message;
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<style scoped>
.modal-overlay {
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
.modal-content {
  background-color: white;
  padding: 2rem;
  border-radius: 8px;
  box-shadow: 0 5px 15px rgba(0,0,0,0.3);
  width: 90vw;
  max-width: 500px;
}
h3 {
  margin-top: 0;
  margin-bottom: 1.5rem;
  text-align: center;
}
.form-group {
  margin-bottom: 1rem;
}
.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 500;
  font-size: 0.9em;
}
.form-group input, .form-group select {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 1em;
  box-sizing: border-box;
}
.date-inputs {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.75rem;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 1rem;
  margin-top: 1.5rem;
}
button {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1em;
  transition: background-color 0.2s;
  background-color: #007bff;
  color: white;
}
button:hover:not(:disabled) {
  background-color: #0056b3;
}
button:disabled {
  background-color: #a0a0a0;
  cursor: not-allowed;
}
.button-secondary {
  background-color: #6c757d;
}
.button-secondary:hover {
  background-color: #5a6268;
}
.error-message {
  color: #d93025;
  text-align: center;
  margin-top: 1rem;
}

/* --- NEW STYLES for picture management --- */
.picture-management {
  display: flex;
  align-items: center;
  gap: 1rem;
}
.avatar-preview {
  width: 60px;
  height: 60px;
  border-radius: 50%;
  object-fit: cover;
  border: 2px solid #e0e0e0;
}
.picture-actions {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
.picture-actions button {
  padding: 0.5rem 1rem; /* Smaller padding for these buttons */
}
.button-danger {
  background-color: #e74c3c;
}
.button-danger:hover {
  background-color: #c0392b;
}
</style>