
<template>
  <div class="admin-container">
    <h1>{{ $t('admin.title') }}</h1>
    <div v-if="isLoading" class="loading-spinner"></div>
    <p v-if="error" class="error-message">{{ error }}</p>
    <div v-if="!isLoading && !error" class="birthday-list-admin">
      <table>
        <thead>
          <tr>
            <th>{{ $t('admin.table.photo') }}</th>
            <th>{{ $t('admin.table.name') }}</th>
            <th>{{ $t('admin.table.birthday') }}</th>
            <th>{{ $t('admin.table.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="person in birthdays" :key="person.id">
            <td>
              <img :src="person.profile_picture_url || defaultAvatar" @error="onImageError" class="avatar" />
            </td>
            <td>{{ person.name }}</td>
            <td>{{ formatDate(person) }}</td>
            <td class="actions">
              <button @click="startEdit(person)" class="edit-btn">{{ $t('admin.edit') }}</button>
              <button @click="confirmDelete(person)" class="delete-btn">{{ $t('admin.delete') }}</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <EditBirthdayModal
      v-if="editingPerson"
      :person="editingPerson"
      @close="cancelEdit"
      @updated="onBirthdayUpdated"
    />
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import defaultAvatar from '../assets/birthday.svg'; // Using existing asset as a placeholder
import EditBirthdayModal from './EditBirthdayModal.vue';

const { t, locale } = useI18n();
const birthdays = ref([]);
const isLoading = ref(true);
const error = ref(null);
const editingPerson = ref(null);

const fetchBirthdays = async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const response = await fetch('/api/birthdays');
    if (!response.ok) {
      throw new Error('Failed to fetch birthdays');
    }
    const data = await response.json();
    birthdays.value = data.sort((a, b) => a.name.localeCompare(b.name));
  } catch (e) {
    error.value = e.message;
  } finally {
    isLoading.value = false;
  }
};

const formatDate = (person) => {
  if (!person.year || !person.month || !person.day) return 'N/A';
  const date = new Date(person.year, person.month - 1, person.day);
  return date.toLocaleDateString(locale.value, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
};

const onImageError = (event) => {
  event.target.src = defaultAvatar;
};

const startEdit = (person) => {
  editingPerson.value = { ...person }; // Create a copy to avoid mutating the original
};

const cancelEdit = () => {
  editingPerson.value = null;
};

const onBirthdayUpdated = () => {
  editingPerson.value = null;
  fetchBirthdays(); // Re-fetch the list to show updated data
};

const confirmDelete = async (person) => {
  if (window.confirm(t('admin.confirmDelete', { name: person.name }))) {
    try {
      const response = await fetch(`/api/birthdays/${person.id}`, {
        method: 'DELETE',
      });
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.message || 'Failed to delete birthday');
      }
      // Remove from list locally for instant feedback
      birthdays.value = birthdays.value.filter(b => b.id !== person.id);
    } catch (e) {
      error.value = e.message;
      // Re-fetch to ensure UI is in sync with backend state on error
      fetchBirthdays();
    }
  }
};

onMounted(fetchBirthdays);
</script>

<style scoped>
.admin-container {
  max-width: 900px;
  margin: 2rem auto;
  padding: 2rem;
  background-color: #fff;
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0,0,0,0.1);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
h1 {
  text-align: center;
  margin-bottom: 2rem;
  color: #2d3748;
}
.loading-spinner {
  border: 4px solid #f3f3f3;
  border-top: 4px solid #3498db;
  border-radius: 50%;
  width: 40px;
  height: 40px;
  animation: spin 1s linear infinite;
  margin: 2rem auto;
}
@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
.error-message {
  color: #d93025;
  text-align: center;
  padding: 1rem;
  background-color: #fef2f2;
  border: 1px solid #fecaca;
  border-radius: 4px;
}
table {
  width: 100%;
  border-collapse: collapse;
}
th, td {
  padding: 1rem;
  text-align: left;
  border-bottom: 1px solid #e2e8f0;
  vertical-align: middle;
}
th {
  background-color: #f7fafc;
  font-weight: 600;
  color: #4a5568;
}
.avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  object-fit: cover;
}
.actions {
  display: flex;
  gap: 0.5rem;
}
.actions button {
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 4px;
  color: white;
  cursor: pointer;
  transition: background-color 0.2s;
  font-size: 0.9em;
}
.edit-btn {
  background-color: #3498db;
}
.edit-btn:hover {
  background-color: #2980b9;
}
.delete-btn {
  background-color: #e74c3c;
}
.delete-btn:hover {
  background-color: #c0392b;
}
</style>