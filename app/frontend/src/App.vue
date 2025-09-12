<script setup>
import { ref, onMounted, computed, watch, defineAsyncComponent } from 'vue'
import { useI18n } from 'vue-i18n'
import BirthdayList from './components/BirthdayList.vue'
import AddBirthdayForm from './components/AddBirthdayForm.vue'
import CalendarView from './components/CalendarView.vue'
import BirthdayComparison from './components/BirthdayComparison.vue'
const WizExerciseModal = defineAsyncComponent(() => import('./components/WizExerciseModal.vue'))
// 1. Import the new AdminView component
import AdminView from './components/AdminView.vue'

// --- COMPONENT SETUP ---

const { locale } = useI18n()

// --- REACTIVE STATE ---

const birthdays = ref([])
const error = ref(null)
const currentView = ref('list') // 'list' or 'calendar'
const showAddForm = ref(false) // Controls visibility of the add form
const selectedIds = ref([]) // Holds the IDs of selected birthdays
const showWizModal = ref(false)

// This computed property will check the URL path
const adminMode = computed(() => {
  // In a real app with vue-router, this would be more robust.
  // For this project, checking the pathname is sufficient.
  return window.location.pathname.startsWith('/admin')
})

// --- LANGUAGE PERSISTENCE ---

// On page load, check for a saved language in localStorage.
const savedLocale = localStorage.getItem('birthday_bot_locale')
if (savedLocale) {
  locale.value = savedLocale
}

// Watch for changes to the locale and save the new value to localStorage.
watch(locale, (newLocale) => {
  localStorage.setItem('birthday_bot_locale', newLocale)
})

// --- METHODS ---

async function fetchBirthdays() {
  try {
    const response = await fetch('/api/birthdays')
    if (!response.ok) {
      throw new Error('Failed to fetch birthdays')
    }
    birthdays.value = await response.json()
    error.value = null
  } catch (e) {
    error.value = e.message
    birthdays.value = []
  }
}

function handleBirthdayAdded() {
  fetchBirthdays() // Refresh the list
  showAddForm.value = false // Hide the form
}

function toggleSelection(id) {
  const index = selectedIds.value.indexOf(id)
  if (index > -1) {
    selectedIds.value.splice(index, 1)
  } else {
    selectedIds.value.push(id)
  }
}

// Fetch initial data when the component is mounted.
onMounted(fetchBirthdays)

// --- COMPUTED PROPERTIES ---

/**
 * Processes the raw birthday data into a sorted and decorated list for display.
 */
const processedBirthdays = computed(() => {
  if (!birthdays.value.length) return []

  const now = new Date()
  const currentYear = now.getFullYear()
  const today = { month: now.getMonth() + 1, day: now.getDate() }

  return birthdays.value
    .map(person => {
      const birthDate = new Date(person.year, person.month - 1, person.day)
      const birthMonthDay = { month: person.month, day: person.day }

      const nextBirthdayYear =
        birthMonthDay.month < today.month ||
        (birthMonthDay.month === today.month && birthMonthDay.day < today.day)
          ? currentYear + 1
          : currentYear

      const nextBirthdayDate = new Date(nextBirthdayYear, person.month - 1, person.day)
      const age = nextBirthdayYear - person.year
      const daysUntilNextBirthday = Math.ceil((nextBirthdayDate - now) / (1000 * 60 * 60 * 24))
      const monthName = nextBirthdayDate.toLocaleString(locale.value, { month: 'long' })
      const weekdayString = nextBirthdayDate.toLocaleString(locale.value, { weekday: 'long' })

      return {
        ...person,
        age,
        nextBirthdayDate,
        daysUntilNextBirthday,
        monthName: monthName.charAt(0).toUpperCase() + monthName.slice(1),
        weekday: weekdayString.charAt(0).toUpperCase() + weekdayString.slice(1)
      }
    })
    .sort((a, b) => a.nextBirthdayDate - b.nextBirthdayDate)
})

const selectedBirthdays = computed(() => {
  return processedBirthdays.value.filter(p => selectedIds.value.includes(p.id))
})

const showComparison = computed(() => {
  return selectedBirthdays.value.length >= 2
})
</script>

<template>
  <div id="app-container">
    <!-- 2. Conditionally render the AdminView or the main application -->
    <AdminView v-if="adminMode" :birthdays="processedBirthdays" />

    <template v-else>
      <header>
        <h1>{{ $t('appTitle') }}</h1>
        <div class="controls">
          <div class="view-switcher">
            <button @click="currentView = 'list'" :class="{ active: currentView === 'list' }">
              {{ $t('listView') }}
            </button>
            <button @click="currentView = 'calendar'" :class="{ active: currentView === 'calendar' }">
              {{ $t('calendarView') }}
            </button>
          </div>
          <div class="locale-slider">
            <button @click="locale = 'en'" :class="{ active: locale === 'en' }">
              English
            </button>
            <button @click="locale = 'es'" :class="{ active: locale === 'es' }">
              Español
            </button>
          </div>
          <div>
            <button class="wiz-btn" @click="showWizModal = true">{{ $t('wiz.button') }}</button>
          </div>
        </div>
      </header>

      <main>
        <WizExerciseModal v-if="showWizModal" @close="showWizModal = false" />
        <div class="add-birthday-container">
          <button @click="showAddForm = !showAddForm" class="add-birthday-button">
            {{ showAddForm ? $t('cancel') : $t('addButton') + ' +' }}
          </button>
          <transition name="slide-fade">
            <div v-if="showAddForm" class="form-wrapper">
              <AddBirthdayForm @birthday-added="handleBirthdayAdded" />
            </div>
          </transition>
        </div>

        <div v-if="error" class="error-message">
          <p>{{ $t('errorFetching') }}: {{ error }}</p>
        </div>

        <div v-else>
          <transition name="layout-fade" mode="out-in">
            <div class="main-content" :class="{ 'comparison-active': showComparison }">
              <div class="list-view-wrapper">
                <transition name="fade" mode="out-in">
                  <div v-if="currentView === 'list'">
                    <BirthdayList
                      :birthdays="processedBirthdays"
                      :selected-ids="selectedIds"
                      @toggle-selection="toggleSelection"
                    />
                  </div>
                  <div v-else-if="currentView === 'calendar'">
                    <CalendarView :birthdays="birthdays" />
                  </div>
                </transition>
              </div>
              <div v-if="showComparison" class="comparison-view-wrapper">
                <BirthdayComparison :birthdays="selectedBirthdays" />
              </div>
            </div>
          </transition>
        </div>
      </main>
    </template>
  </div>
</template>

<style scoped>
#app-container {
  max-width: 1400px; /* Widen the container for the new layout */
  margin: 2rem auto;
  padding: 2rem;
  background-color: #fff;
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
}

/* 3. Add a rule to remove padding when in admin mode for a cleaner look */
#app-container:has(> .admin-container) {
  padding: 0;
}

header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid #e2e8f0;
  padding-bottom: 1rem;
  margin-bottom: 1rem;
}

h1 {
  color: #2d3748;
  font-size: 2rem;
}

.controls {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.view-switcher,
.locale-slider {
  display: flex;
  border: 1px solid #ccc;
  border-radius: 6px;
  overflow: hidden;
}

.view-switcher button,
.locale-slider button {
  padding: 0.5rem 1rem;
  border: none;
  background-color: transparent;
  cursor: pointer;
  transition: background-color 0.2s;
  font-size: 0.9em;
}

.view-switcher button.active,
.locale-slider button.active {
  background-color: #007bff;
  color: white;
}

.wiz-btn {
  background-color: #007bff;
  color: #fff;
  border: none;
  padding: 0.5rem 1rem;
  font-size: 0.9em;
  border-radius: 6px;
  cursor: pointer;
  transition: background-color 0.2s;
  line-height: 1.1;
}
.wiz-btn:hover {
  background-color: #0056b3;
}
.wiz-btn:focus {
  outline: 2px solid #0056b3;
  outline-offset: 2px;
}

.main-content {
  display: grid;
  grid-template-columns: 1fr;
  gap: 2rem;
  transition: grid-template-columns 1.0s ease-in-out;
}

.main-content.comparison-active {
  grid-template-columns: 1fr 1fr; /* Two-column layout */
}

.list-view-wrapper {
  transition: all 1.0s ease-in-out;
}



.error-message {
  color: #e53e3e;
  background-color: #fff5f5;
  border: 1px solid #fc8181;
  padding: 1rem;
  border-radius: 6px;
  text-align: center;
}

.add-birthday-container {
  margin-bottom: 2rem;
  text-align: center;
}

.add-birthday-button {
  background-color: #007bff;
  color: white;
  border: none;
  padding: 0.75rem 1.5rem;
  font-size: 1rem;
  border-radius: 6px;
  cursor: pointer;
  transition: background-color 0.2s;
}

.add-birthday-button:hover {
  background-color: #0056b3;
}

.form-wrapper {
  margin-top: 1rem;
}

/* Transitions */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.slide-fade-enter-active {
  transition: all 0.3s ease-out;
}

.slide-fade-leave-active {
  transition: all 0.3s cubic-bezier(1, 0.5, 0.8, 1);
}

.slide-fade-enter-from,
.slide-fade-leave-to {
  transform: translateY(-20px);
  opacity: 0;
}

.layout-fade-enter-active,
.layout-fade-leave-active {
  transition: opacity 0.5s ease;
}
.layout-fade-enter-from,
.layout-fade-leave-to {
  opacity: 0;
}
</style>