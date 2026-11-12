type Props = { value: string; onInput: (value: string) => void; placeholder?: string };

export const SearchField = ({ value, onInput, placeholder = "Search anything…" }: Props) => (
  <label class="rt-search">
    <svg class="rt-search__icon" viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="7" cy="7" r="5" fill="none" stroke="currentColor" stroke-width="1.6" />
      <path d="M11 11l3.5 3.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
    </svg>
    <input class="rt-search__input" type="search" value={value} placeholder={placeholder} onInput={(event) => onInput(event.currentTarget.value)} />
    {value && (
      <button type="button" class="rt-search__clear" aria-label="Clear" onClick={() => onInput("")}>
        ×
      </button>
    )}
  </label>
);
