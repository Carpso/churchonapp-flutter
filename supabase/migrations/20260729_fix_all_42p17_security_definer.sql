-- Fix all SECURITY DEFINER functions missing SET search_path = public
-- These cause 42P17 "column does not exist" errors when the search_path
-- doesn't include the public schema

ALTER FUNCTION public.add_coins(user_id uuid, amount integer) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.auto_join_community_group() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.end_business_meeting(p_meeting_id uuid, p_user_id uuid) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.generate_meeting_code() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.increment_fundraising_raised(venture_id uuid, amount double precision) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.increment_group_collected(group_id uuid, amount double precision) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.increment_member_paid(member_id uuid, amount double precision) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.join_business_meeting(p_meeting_id uuid, p_user_id uuid, p_role text) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.link_pre_registration() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.start_business_meeting(p_meeting_id uuid, p_user_id uuid) SECURITY DEFINER SET search_path = public;
