type Tab<Id extends string> = { id: Id; label: string };
type Props<Id extends string> = { tabs: Tab<Id>[]; selected: Id; onSelect: (id: Id) => void };

// A gray track with a raised segment for the selected tab.
export const TabStrip = <Id extends string>({ tabs, selected, onSelect }: Props<Id>) => (
  <div class="rt-tabs" role="tablist">
    {tabs.map(({ id, label }) => (
      <button type="button" role="tab" class="rt-tab" aria-selected={id === selected} key={id} onClick={() => onSelect(id)}>
        {label}
      </button>
    ))}
  </div>
);
