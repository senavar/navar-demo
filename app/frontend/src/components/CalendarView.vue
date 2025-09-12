<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'

const { t, locale } = useI18n()

// This component receives the raw birthday list from its parent.
const props = defineProps({
  birthdays: {
    type: Array,
    required: true
  }
})

// --- REACTIVE STATE ---
const currentDate = ref(new Date())

// --- COMPUTED PROPERTIES ---

// Automatically formats the header (e.g., "August 2025") based on the current date and locale.
const monthYearHeader = computed(() => {
  const header = currentDate.value.toLocaleString(locale.value, {
    month: 'long',
    year: 'numeric'
  })
  // Capitalize the first letter to ensure consistency across locales.
  return header.charAt(0).toUpperCase() + header.slice(1)
})

// Automatically generates the day names header (e.g., Sun, Mon, Tue...) in the correct locale order.
const dayNames = computed(() => {
  const formatter = new Intl.DateTimeFormat(locale.value, { weekday: 'short' })
  // Start from a Sunday (e.g., 2023-01-01) to ensure correct ordering
  const names = [...Array(7).keys()].map(day => formatter.format(new Date(2023, 0, day + 1)))
  // Capitalize each day name for a consistent look.
  return names.map(name => name.charAt(0).toUpperCase() + name.slice(1))
})

// The core logic: generates the grid of days for the current month.
const calendarGrid = computed(() => {
  const year = currentDate.value.getFullYear()
  const month = currentDate.value.getMonth()
  const firstDayOfMonth = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()

  const grid = []
  // Add padding cells for the start of the month.
  for (let i = 0; i < firstDayOfMonth; i++) {
    grid.push({ isPadding: true })
  }

  // Add cells for each day of the month.
  for (let i = 1; i <= daysInMonth; i++) {
    grid.push({
      dayNumber: i,
      // Find all birthdays from the raw data that fall on this specific day.
      birthdays: props.birthdays.filter(b => b.month === month + 1 && b.day === i)
    })
  }
  return grid
})

// --- METHODS ---

function prevMonth() {
  currentDate.value = new Date(currentDate.value.setMonth(currentDate.value.getMonth() - 1))
}

function nextMonth() {
  currentDate.value = new Date(currentDate.value.setMonth(currentDate.value.getMonth() + 1))
}
</script>

<template>
  <div class="calendar-container">
    <div class="calendar-header">
      <button @click="prevMonth">&lt; {{ $t('prev') }}</button>
      <h3>{{ monthYearHeader }}</h3>
      <button @click="nextMonth">{{ $t('next') }} &gt;</button>
    </div>

    <div class="calendar-grid">
      <div v-for="name in dayNames" :key="name" class="calendar-day-name">
        {{ name }}
      </div>
      <div
        v-for="(day, index) in calendarGrid"
        :key="index"
        :class="['calendar-day', { 'other-month': day.isPadding }]"
      >
        <div v-if="!day.isPadding">
          <div class="day-number">{{ day.dayNumber }}</div>
          <div class="events-container">
            <div
              v-for="birthday in day.birthdays"
              :key="birthday.id"
              class="birthday-event"
            >
              {{ birthday.name }} ({{ currentDate.getFullYear() - birthday.year }})
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.calendar-container {
  margin-top: 2rem;
}

.calendar-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.calendar-header h3 {
  margin: 0;
  color: #2d3748;
  font-size: 1.5rem;
}

.calendar-header button {
  background-color: #f8f9fa;
  border: 1px solid #dee2e6;
  padding: 0.5rem 1rem;
  cursor: pointer;
  border-radius: 6px;
  transition: background-color 0.2s;
}

.calendar-header button:hover {
  background-color: #e9ecef;
}

.calendar-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 1px;
  background-color: #e2e8f0;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  overflow: hidden;
}

.calendar-day-name {
  font-weight: bold;
  text-align: center;
  padding: 0.5rem 0;
  background-color: #f8f9fa;
  color: #4a5568;
}

.calendar-day {
  background-color: #fff;
  min-height: 120px;
  padding: 8px;
  display: flex;
  flex-direction: column;
}

.calendar-day.other-month {
  background-color: #f7fafc;
}

.day-number {
  font-weight: 500;
  font-size: 0.9em;
  color: #718096;
  margin-bottom: 4px;
}

.events-container {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.birthday-event {
  font-size: 0.85em;
  padding: 4px 6px;
  background-color: #e6f7ff;
  border-left: 3px solid #1890ff;
  border-radius: 2px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #0d47a1;
}
</style>