-- Allow updating bible study member roles (e.g. when replacing group leader)

CREATE POLICY "Org members can update bible study group members"
  ON public.bible_study_group_members FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.bible_study_groups bsg
      JOIN public.organization_members om ON om.organization_id = bsg.organization_id
      WHERE bsg.id = bible_study_group_members.bible_study_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.bible_study_groups bsg
      JOIN public.organization_members om ON om.organization_id = bsg.organization_id
      WHERE bsg.id = bible_study_group_members.bible_study_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
