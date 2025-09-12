<script setup>
import { ref, watch, onMounted, onUnmounted, nextTick } from 'vue' // Import nextTick
import { useI18n } from 'vue-i18n'

// --- COMPONENT SETUP ---

const { t } = useI18n()

const props = defineProps({
  birthdays: {
    type: Array,
    required: true
  },
  selectedIds: {
    type: Array,
    default: () => []
  }
})

const emit = defineEmits(['toggle-selection'])

const defaultAvatar = "data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3e%3crect width='100' height='100' fill='%23e0e0e0'/%3e%3cpath d='M50 40 A15 15 0 1 0 50 10 A15 15 0 1 0 50 40 M25 90 A40 40 0 0 1 75 90' fill='none' stroke='%23a0a0a0' stroke-width='5'/%3e%3c/svg%3e"

function handleImageError(event) {
  event.target.src = defaultAvatar
}

function toggleSelection(id) {
  emit('toggle-selection', id)
}

// --- INFINITE SCROLL LOGIC ---

const displayedBirthdays = ref([])
const itemsPerLoad = 5
let nextItemIndex = 0
const loadMoreTrigger = ref(null)
let observer = null
const scrollContainer = ref(null)

const loadMore = () => {
  if (nextItemIndex >= props.birthdays.length) {
    return
  }
  const newItems = props.birthdays.slice(nextItemIndex, nextItemIndex + itemsPerLoad)
  displayedBirthdays.value.push(...newItems)
  nextItemIndex += itemsPerLoad
}

// NEW: A dedicated function to set up the observer.
const setupObserver = () => {
  // Clean up any old observer
  if (observer) observer.disconnect()

  // Ensure the scroll container is in the DOM before proceeding
  if (!scrollContainer.value) return

  const options = {
    root: scrollContainer.value, // Watch for scrolling inside our list
    rootMargin: '0px 0px 200px 0px' // Trigger when 200px from the bottom
  }

  observer = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting) {
      loadMore()
    }
  }, options)

  if (loadMoreTrigger.value) {
    observer.observe(loadMoreTrigger.value)
  }
}

// MODIFIED: The reset function is now async to use nextTick
const resetAndLoadInitial = async () => {
  displayedBirthdays.value = []
  nextItemIndex = 0
  if (scrollContainer.value) {
    scrollContainer.value.scrollTop = 0
  }
  loadMore()

  // KEY FIX: Wait for the DOM to update after loading initial items
  await nextTick()
  // Now that the DOM is ready, set up the observer on the correct elements
  setupObserver()
}

// The watcher will now correctly re-initialize the observer when the list changes
watch(() => props.birthdays, resetAndLoadInitial, { deep: true })

// --- LIFECYCLE HOOKS ---

onMounted(() => {
  // This will load initial items and set up the observer correctly
  resetAndLoadInitial()
})

onUnmounted(() => {
  if (observer) {
    observer.disconnect()
  }
})
</script>

<template>
  <div class="list-container">
    <h2>{{ $t('upcomingBirthdays') }}</h2>
    <!-- The ref on the <ul> is still correct -->
    <ul v-if="displayedBirthdays.length" ref="scrollContainer">
      <li v-for="person in displayedBirthdays" :key="person.id"
          class="birthday-item"
          :class="{ selected: selectedIds.includes(person.id) }"
          @click="toggleSelection(person.id)">
        <img
          :src="person.profile_picture_url || defaultAvatar"
          alt="Profile picture"
          loading="lazy"
          class="avatar"
          @error="handleImageError"
        />
        <div class="calendar-icon">
          <div class="month">{{ person.monthName.substring(0, 3) }}</div>
          <div class="day">{{ person.day }}</div>
        </div>
        <div class="birthday-info">
          <span class="name">{{ person.name }}</span>
          <span class="details">
            {{ $t('onDate', { weekday: person.weekday, month: person.monthName, day: person.day, year: person.nextBirthdayDate.getFullYear() }) }}
          </span>
        </div>
        <div class="birthday-meta">
          <span class="age">{{ $t('turnsAge', { age: person.age }) }}</span>
          <span class="daysUntilNextBirthday">{{ $t('daysUntilNextBirthday', { count: person.daysUntilNextBirthday }) }}</span>
        </div>
      </li>
      <!-- The trigger element is still correct -->
      <div ref="loadMoreTrigger"></div>
    </ul>
    <p v-else class="no-birthdays">{{ $t('noBirthdays') }}</p>
  </div>
</template>

<style scoped>
/* Your styles remain unchanged */
.list-container {
  margin-top: 2rem;
}

h2 {
  border-bottom: 1px solid #ddd;
  padding-bottom: 0.5rem;
  color: #2d3748;
}

ul {
  list-style: none;
  padding: 0;
  margin-top: 1rem;
  max-height: 60vh;
  overflow-y: auto;
  padding-right: 0.5rem;
}

li {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  border-radius: 6px;
  background-color: #f8f9fa;
  margin-bottom: 0.75rem;
  transition: box-shadow 0.2s, transform 0.2s;
}

li:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 8px rgba(0,0,0,0.08);
}

li.selected {
  border-color: #007bff;
  box-shadow: 0 4px 12px rgba(0, 123, 255, 0.2);
  background-color: #e7f3ff;
}

.avatar {
  width: 50px;
  height: 50px;
  border-radius: 50%;
  object-fit: cover;
  border: 2px solid #e0e0e0;
  flex-shrink: 0;
}

.calendar-icon {
  border: 1px solid #dee2e6;
  border-radius: 4px;
  text-align: center;
  width: 50px;
  flex-shrink: 0;
  font-size: 0.8em;
  background-color: #fff;
}

.calendar-icon .month {
  background-color: #007bff;
  color: white;
  padding: 2px 0;
  border-top-left-radius: 3px;
  border-top-right-radius: 3px;
  text-transform: uppercase;
  font-weight: bold;
}

.calendar-icon .day {
  padding: 5px 0;
  font-size: 1.4em;
  font-weight: bold;
  color: #495057;
}

.birthday-info {
  display: flex;
  flex-direction: column;
  flex-grow: 1;
}

.name {
  font-weight: bold;
  font-size: 1.1em;
  color: #343a40;
}

.details {
  color: #6c757d;
  font-size: 0.9em;
}

.birthday-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  flex-shrink: 0;
}

.age {
  font-weight: bold;
  font-size: 1.1em;
  color: #343a40;
}

.weekday {
  font-size: 0.9em;
  color: #6c757d;
}

.no-birthdays {
  margin-top: 1rem;
  color: #6c757d;
  text-align: center;
  padding: 2rem;
  background-color: #f8f9fa;
  border-radius: 6px;
}
</style>