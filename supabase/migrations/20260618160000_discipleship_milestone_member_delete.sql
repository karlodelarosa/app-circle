-- Allow org members (not just admins) to delete milestones on their tracks

CREATE POLICY "Org members can delete discipleship milestones"
  ON public.discipleship_milestones FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_milestones.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
