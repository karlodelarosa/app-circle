-- Prayer wall: lightweight prayer requests per discipleship group, visible to
-- any org staff/leader who can already see the group.

CREATE TABLE public.discipleship_group_prayer_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.discipleship_groups(id) ON DELETE CASCADE,
  person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  is_answered BOOLEAN NOT NULL DEFAULT false,
  answered_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX discipleship_group_prayer_items_group_id_idx
  ON public.discipleship_group_prayer_items(group_id);
CREATE INDEX discipleship_group_prayer_items_person_id_idx
  ON public.discipleship_group_prayer_items(person_id);
CREATE INDEX discipleship_group_prayer_items_created_at_idx
  ON public.discipleship_group_prayer_items(created_at DESC);
ALTER TABLE public.discipleship_group_prayer_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view discipleship group prayer items"
  ON public.discipleship_group_prayer_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_prayer_items.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship group prayer items"
  ON public.discipleship_group_prayer_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_prayer_items.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update discipleship group prayer items"
  ON public.discipleship_group_prayer_items FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_prayer_items.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_prayer_items.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete discipleship group prayer items"
  ON public.discipleship_group_prayer_items FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_prayer_items.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
