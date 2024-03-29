#include maps\_specialops;

// ---------------------------------------------------------------------------------

fire_off_exploder(current)
{
	while (true)
	{
		common_scripts\_exploder::exploder(current.script_prefab_exploder);
		if (!isdefined(current.target))
			break;
		next = getent(current.target, "targetname");
		if (!isdefined(next))
			break;
		current = next;
	}
}

// ---------------------------------------------------------------------------------

create_smoke_wave(smoke_tag, flag_start, dialog_wait)
{
	if (isdefined(flag_start))
	{
		common_scripts\utility::flag_init(flag_start);
		common_scripts\utility::flag_wait(flag_start);
	}

	// prevent smoke from happening too frequently
	if (isdefined(level.smoke_throttle))
	{
		if (!isdefined(level.smoke_wave_time))
			level.smoke_wave_time = gettime() - level.smoke_throttle - 1;
	
		time_since = gettime() - level.smoke_wave_time;
		if (time_since <= level.smoke_throttle)
			return;
	
		level.smoke_wave_time = gettime();
	}
	
	magic_smoke_grenades = getentarray(smoke_tag, "targetname");
	common_scripts\utility::array_thread(magic_smoke_grenades, ::smoke_wave_play);

	// undefined dialog_wait assumes we don't want any. use 0 for no wait.
	if (isdefined(dialog_wait))
		thread dialog_smoke_wave_alert(dialog_wait);
}

smoke_wave_play()
{
	playfx(common_scripts\utility::getfx("smokescreen"), self.origin);
	self thread common_scripts\utility::play_sound_in_space("smokegrenade_explode_default");
}

dialog_smoke_wave_alert(dialog_wait)
{	
	level endon("special_op_terminated");
	
	wait dialog_wait;

	//hunter two-one, overlord. advise switching to thermal optics, over.
	maps\_utility::radio_dialogue("so_def_inv_thermaloptics");
}

// ---------------------------------------------------------------------------------

btr80_level_init()
{
	if (isdefined(level.btr_init))
		return;
		
	level.btr_init = true;
	level.btr80_count = 0;

	if (!isdefined(level.btr_min_fighting_range))
		level.btr_min_fighting_range = 400;

	if (!isdefined(level.btr_max_fighting_range))
		level.btr_max_fighting_range = 2400;

	if (!isdefined(level.btr_target_fov))
		level.btr_target_fov = cos(50);
		
	level.btr80_building_checks = getentarray("trigger_multiple_flag_set_touching", "classname");
	
	for (i = level.btr80_building_checks.size - 1; i >= 0; i--)
	{
		building = level.btr80_building_checks[i];
		if (!isdefined(building.script_flag))
		{
			level.btr80_building_checks[i] = undefined;
			continue;
		}
			
		switch(building.script_flag)
		{
			case "player_inside_nates"	:
			case "player_in_burgertown"	:
			case "player_in_diner"		:
				// do nothing, keep in the list.
				break;
			default:
				level.btr80_building_checks[i] = undefined;
				break;
		}
	}
}

create_btr80(btr80_tag, flag_start)
{
	if (isdefined(flag_start))
	{
		common_scripts\utility::flag_init(flag_start);
		common_scripts\utility::flag_wait(flag_start);
	}

	btr80_level_init();		
	
	btr80 = maps\_vehicle::spawn_vehicle_from_targetname_and_drive(btr80_tag);
	common_scripts\utility::array_thread(getvehiclenodearray("new_target", "script_noteworthy"), ::btr80_new_target_think);
	
	btr80 thread btr80_watch_for_player();
	btr80 thread btr80_register_death();
	btr80 thread maps\_utility::ent_flag_init("spotted_player");
	btr80 thread btr80_turret_spotlight();
	btr80 thread maps\_vehicle_code::damage_hints();
	btr80 thread dialog_btr80_spotted_you();
}

btr80_watch_for_player()
{
	level endon("special_op_terminated");
	self endon("death");
	self.turret_busy = false;
	
	while (true)
	{
		wait .05;

		if (self maps\_utility::ent_flag("spotted_player"))
			continue;

		player = btr80_find_available_player();
		if (!isdefined(player))
			continue;

		tag_flash_angles = self gettagangles("tag_flash");
		if (!common_scripts\utility::within_fov(self.origin, tag_flash_angles, player.origin, level.btr_target_fov))
			continue;

		if (!btr80_can_see_player(player))
			continue;

		self notify("new_target");				// clears ambient target shooting
		self.turret_busy = true;
		self maps\_utility::ent_flag_set("spotted_player");
		player.btr80_attacker_id = self.unique_id;	// claim this player for myself.
		self vehicle_setspeed(0, 10);
		
		//saw player, now miss for 2 bursts
		btr80_miss_player(player);
		wait(randomfloatrange(0.8, 2.4));
		btr80_miss_player(player);
		wait(randomfloatrange(0.8, 2.4));
    	
		//if player is still exposed then hit him
		while (btr80_can_see_player(player))
		{
			btr80_fire_at_player(player);
			wait(randomfloatrange(0.5, 1.5));
		}
		
        self clearturrettargetent();
		self.turret_busy = false;
		self maps\_utility::ent_flag_clear("spotted_player");
		player.btr80_attacker_id = undefined;
		self vehicle_setspeed(10, 1);
	}
}

btr80_turret_spotlight()
{
	maps\_vehicle::vehicle_lights_on("spotlight spotlight_turret");
}

btr80_fire_at_player(player)
{
	self endon("death");
	burstsize = randomintrange(3, 5);
	firetime = .2;
	for (i = 0; i < burstsize; i++)
	{
		self setturrettargetent(player, common_scripts\utility::randomvector(20) + (0, 0, 32));//randomvec was 50
		self fireweapon();
		wait firetime;
	}
}

btr80_miss_player(player)
{
	self endon("death");
	
	//point in front of player
	forward = anglestoforward(player.angles);
	forwardfar = forward * 100;
	miss_vec = forwardfar + common_scripts\utility::randomvector(50);
	
	burstsize = randomintrange(4, 6);
	firetime = .2;
	for (i = 0; i < burstsize; i++)
	{
		offset = common_scripts\utility::randomvector(15) + miss_vec + (0,0,64);
		self setturrettargetent(player, offset);
		self fireweapon();
		wait firetime;
	}
}

btr80_find_available_player()
{
	p1_ok = btr80_check_player_available(level.player)  && btr80_check_player_in_range(level.player);
	p2_ok = btr80_check_player_available(level.player2) && btr80_check_player_in_range(level.player2);

	if (p1_ok && p2_ok)
		return common_scripts\utility::getclosest(self.origin, level.players);
	
	if (p1_ok)
		return level.player;

	if (p2_ok)
		return level.player2;
		
	return undefined;
}

btr80_check_player_available(player)
{
	if (!isdefined(player))
		return false;
	
	if (isdefined(player.btr80_attacker_id))
		return false;
		
	return true;
}

btr80_check_player_in_range(player)
{
	if (!isdefined(player))
		return false;
		
	if (distance(self.origin, player.origin) > level.btr_max_fighting_range)
		return false;

	if (distance(self.origin, player.origin) < level.btr_min_fighting_range)
		return false;
		
	return true;
}

btr80_check_player_in_building(player)
{
	if (!isdefined(player))
		return;
		
	foreach (building in level.btr80_building_checks)
	{
		if (player istouching(building))
			return true;
	}
	
	return false;
}

btr80_can_see_player(player)
{
	if (btr80_check_player_in_building(player))
		return false;
		
	if (!btr80_check_player_in_range(player))
		return false;
		
	tag_flash_loc = self gettagorigin("tag_flash");
	player_eye = player geteye();
	return sighttracepassed(tag_flash_loc, player_eye, false, self);
}

btr80_new_target_think()
{
	level endon("special_op_terminated");
	level endon("btr80s_all_down");

	targets = getentarray(self.script_linkto, "script_linkname");
	while (true)
	{
		self waittill("trigger", vehicle);
		
		if (!isalive(vehicle))
			return;
		if (vehicle.turret_busy)
			continue;
		
		vehicle notify("new_target");
		
		vehicle setturrettargetent(targets[0]);
		
		thread btr80_fire_at_targets(vehicle);
	}
}

btr80_fire_at_targets(vehicle)
{
	level endon("special_op_terminated");

	vehicle endon("new_target");
	vehicle endon("death");
	
	vehicle waittill("turret_on_target");
		
	while (true)
	{
		s = randomintrange(4, 6);
		for (j = 0; j < s; j++)
		{
				vehicle fireweapon();
				wait .2;
		}
		wait(randomfloatrange(1, 2));
	}
}

btr80_register_death()
{
	level endon("special_op_terminated");

	level.btr80_count++; 

	my_id = self.unique_id;
	thread btr80_challenge_complete_behavior();
	
	self waittill("death", attacker);

	if (attacker == level.player)
    {
		thread pulse_kill_counter_hud(level.btr_kill_value, 0);
    }

	if (self maps\_utility::ent_flag("spotted_player"))
	{
		foreach (player in level.players)
		{
			if (isdefined(player.btr80_attacker_id) && (my_id == player.btr80_attacker_id))
				player.btr80_attacker_id = undefined;
		}
	}

	level.btr80_count--;
	/#
	assertex((level.btr80_count >= 0), "somehow the btr80 population counter dropped below 0. this should never happen.");
	#/
	if (level.btr80_count <= 0)
		level notify("btr80s_all_down");
}

btr80_challenge_complete_behavior()
{
	self endon("death");

	level waittill("special_op_terminated");

	self vehicle_setspeed(0, 10);
}

dialog_btr80_spotted_you()
{
	level endon("special_op_terminated");
	self endon("death");

	while (true)
	{
		maps\_utility::ent_flag_wait("spotted_player");
		dialog_btr80_spotted_you_action();
		wait 20;
	}
}

dialog_btr80_spotted_you_action()
{
	spotted_player = undefined;
	foreach (player in level.players)
	{
		if (isdefined(player.btr80_attacker_id) && (player.btr80_attacker_id == self.unique_id))
		{
			spotted_player = player;
			break;
		}
	}
	
	if (!btr80_can_see_player(spotted_player))
		return;

	// prevent btr80 dialog from happening too frequently
	if (isdefined(level.btr80_alert_throttle))
	{
		if (!isdefined(level.btr80_alert_time))
			level.btr80_alert_time = gettime() - level.btr80_alert_throttle - 1;
	
		time_since = gettime() - level.btr80_alert_time;
		if (time_since <= level.btr80_alert_throttle)
			return;
	
		level.btr80_alert_time = gettime();
	}

	//enemy btr has a visual on you, hunter two-one, advise seeking cover, over.
	//hunter two-one, be advised enemy btr is targetting you, over.
	maps\_utility::radio_dialogue("so_def_inv_bmpspottedyou");
}

// ---------------------------------------------------------------------------------

hunter_enemies_level_init()
{
	if (isdefined(level.hunters_init))
		return;

	level.hunters_init = true;
	
	level.hunters_active = 0;
	level.hunter_enemies = [];
	level.hunter_damage_p1 = [];	
	level.hunter_damage_p2 = [];	
	dialog_hunter_enemies_setup();

	maps\_utility::set_group_advance_to_enemy_parameters(60000, 1);

	level.difficultysettings["accuracydistscale"]["easy"] = 0.65;
	level.difficultysettings["accuracydistscale"]["normal"]  = 0.65;
	level.difficultysettings["accuracydistscale"]["hardened"] = 0.5;
	level.difficultysettings["accuracydistscale"]["veteran"]  = 0.4;
	maps\_gameskill::updatealldifficulty();
}

create_hunter_enemy_group(enemy_tag, flag_start, enemy_count)
{
	if (isdefined(flag_start))
	{
		common_scripts\utility::flag_init(flag_start);
		common_scripts\utility::flag_wait(flag_start);
	}
	
	hunter_enemies_level_init();
	
	if (!isdefined(level.hunter_group_initialized))
	{
		level.hunter_group_initialized = true;
		level.hunter_goals = getentarray("closest_goal_radius", "targetname");
	}

	current_enemies = getentarray(enemy_tag, "targetname");
	common_scripts\utility::array_thread(current_enemies, maps\_utility::add_spawn_function, ::create_hunter_enemy);

	if (!isdefined(enemy_count) || (enemy_count > current_enemies.size) )
		enemy_count = current_enemies.size;

	thread dialog_hunter_enemies(enemy_tag, 2.5);

	current_enemies = common_scripts\utility::array_randomize(current_enemies);
	for (i = 0 ; i < enemy_count ; i++)
	{
		current_enemies[i].count = 1;
		guy = current_enemies[i] maps\_utility::spawn_ai();
		wait randomfloat(1);
	}
	
	level notify("hunter_group_spawn_complete");
}

create_hunter_truck_enemies(truck_tag, flag_start)
{
	if (isdefined(flag_start))
	{
		common_scripts\utility::flag_init(flag_start);
		common_scripts\utility::flag_wait(flag_start);
	}
	
	hunter_enemies_level_init();

	if (!isdefined(level.truck_group_initialized))
	{
		level.truck_group_initialized = true;
		truck_group_enemies = getentarray("truck_group_enemies", "script_noteworthy");
		common_scripts\utility::array_thread(truck_group_enemies, maps\_utility::add_spawn_function, ::create_hunter_enemy, true);
	}

	truck = thread maps\_vehicle::spawn_vehicle_from_targetname_and_drive(truck_tag);
	truck.veh_pathtype = "constrained";
}

create_hunter_enemy(wait_for_unload)
{
	self endon("death");
	level endon("special_op_terminated");

	thread hunter_register_damage();
	thread hunter_register_death();
	
	level.hunter_enemies[self.unique_id] = self;
	
	if (isdefined(wait_for_unload) && wait_for_unload)
		self waittill("jumpedout");

	thread hunter_enemy_maintain_closest_goal();
}

hunter_enemy_maintain_closest_goal()
{
	self endon("death");
	level endon("special_op_terminated");

	self maps\_utility::enable_danger_react(5);
	self.goalradius = 3096;
	self.goalheight = 768;
	
	while (true)
	{
		closest_player = common_scripts\utility::getclosest(self.origin, level.players	);
		closest_goal = common_scripts\utility::getclosest(closest_player.origin, level.hunter_goals);
		if (!isdefined(self.current_goal) || (self.current_goal != closest_goal))
		{
			waittillframeend;
			//waittillframeend because you may be in the part of the frame that is before 
			//the script has received the "death" notify but after the ai has died.

			self.current_goal = closest_goal;
			self setgoalpos(self.current_goal.origin);
		}

		wait 1.0;
	}
}

// this should be updated to be more like the one in so_defense_invasion
hunter_enemies_refill(refill_at, min_fill, max_fill)
{
	level endon("special_op_terminated");

	if (!isdefined(refill_at) || (refill_at < 0))
		refill_at = 0;
	if (!isdefined(min_fill) || (min_fill < 1))
		min_fill = 1;
	if (!isdefined(max_fill) || (max_fill <= min_fill))
		max_fill = min_fill + 1;
	
	used_smoke = false;
	last_spawn = "gas";	// level starts off with them coming from the gas station.
	while (true)
	{
		if (!isdefined(level.hunters_active) || (level.hunters_active <= refill_at))
		{
			spawn_options = [];
			if (!common_scripts\utility::flag("so_player_near_bank"))
				spawn_options[spawn_options.size] = "bank";
			if (!common_scripts\utility::flag("so_player_near_gas_station"))
				spawn_options[spawn_options.size] = "gas";
			if (!common_scripts\utility::flag("so_player_near_taco"))
				spawn_options[spawn_options.size] = "taco";
			
			// no "good" options, so just pick a random one.
			if (spawn_options.size <= 0)
			{
				spawn_options[spawn_options.size] = "bank";
				spawn_options[spawn_options.size] = "gas";
				spawn_options[spawn_options.size] = "taco";
			}

			// only try for a new option of we have more than one.
			i = 0;
			if (spawn_options.size > 1)
			{
				i = randomint(spawn_options.size);
				if (spawn_options[i] == last_spawn)
				{
					i--;
					if (i < 0)
						i = spawn_options.size - 1;
				}
			}
					
			respawn_amount = randomintrange(min_fill, max_fill);
			last_spawn = spawn_options[i];
			switch (spawn_options[i])
			{
				case "bank": 
					thread maps\so_killspree_invasion::enable_hunter_enemy_group_bank(respawn_amount);
					if (!used_smoke || randomfloat(1.0) < level.smoke_chance)
					{
						used_smoke = true;
						thread maps\so_killspree_invasion::enable_smoke_wave_north(4);
					}
					break;

				case "gas":  
					thread maps\so_killspree_invasion::enable_hunter_enemy_group_gas_station(respawn_amount);
					break;

				case "taco": 
					thread maps\so_killspree_invasion::enable_hunter_enemy_group_taco(respawn_amount);
					if (!used_smoke || randomfloat(1.0) < level.smoke_chance)
					{
						used_smoke = true;
						thread maps\so_killspree_invasion::enable_smoke_wave_south(4);
					}
					break;
			}
		
			level waittill("hunter_group_spawn_complete");
		}

		// give it a moment before checking again.
		wait 1;
	}
}

hunter_register_damage()
{
	level.hunter_damage_p1[self.unique_id] = 0;	
	level.hunter_damage_p2[self.unique_id] = 0;	
	
	self endon("death");

	while (true)
	{
		self waittill("damage", amount, attacker);
		
		if (!isdefined(attacker))
			continue;
			
		if (attacker == level.player)
		{
			level.hunter_damage_p1[self.unique_id] += amount;
			continue;
		}
	}
}

hunter_register_death()
{
	level endon("special_op_terminated");
	self endon("pain_death");
	
	level.hunters_active++;
	
	my_maxhealth = self.maxhealth;
	my_id = self.unique_id;
	my_noteworthy = self.script_noteworthy;
	my_birthtime = gettime();
	
	thread hunter_register_long_death(my_id);

	self waittill("death", attacker, cause, weapon_name);

	hunter_register_death_score(my_id, attacker, level.hunter_kill_value, my_noteworthy, my_birthtime);
	hunter_register_death_cleanup(my_id);
}

hunter_register_long_death(my_id)
{
	level endon("special_op_terminated");
	self endon("death");

	self waittill("pain_death", attacker);

	thread hunter_register_long_death_finish(my_id);
}

hunter_register_long_death_finish(my_id)
{
	level endon("special_op_terminated");

	level.hunter_damage_p1[my_id] = 0;
	level.hunter_damage_p2[my_id] = 0;

	self waittill("death", attacker, cause);

	if (!isdefined(attacker))
		return;
		
	if (!isplayer(attacker))
		return;

	if (cause == "mod_unknown")
		return;
		
	melee_kill = false;
	if (isdefined(cause) && (cause == "mod_melee"))
		melee_kill = true;

	if (melee_kill)
		hunter_register_death_score(my_id, attacker, level.hunter_brutal_value);
	else
		hunter_register_death_score(my_id, attacker, level.hunter_finish_value);
	
	hunter_register_death_cleanup(my_id);
}

hunter_register_death_cleanup(my_id)
{
	level.hunters_active--;
	level.hunter_enemies[my_id] = undefined;
	level.hunter_damage_p1[my_id] = undefined;
	level.hunter_damage_p2[my_id] = undefined;
}

hunter_register_death_score(my_id, attacker, point_value, my_noteworthy, my_birthtime)
{
	if (attacker == level.player)
	{
		thread pulse_kill_counter_hud(point_value, 0);
	}
	else if (isdefined(self.vehicle_attacker) && self.vehicle_attacker == level.player)
	{
		thread pulse_kill_counter_hud(point_value, 0);
	}
	else
	{
		// only needed for enemies spawning from the trucks. they aren't getting their killer
		// passed on correctly and haven't been able to track down where they are getting killed from.
		if (!isdefined(my_noteworthy) || (my_noteworthy != "truck_group_enemies"))
			return;

		// only fudge for 25 seconds after spawning.
		if (!isdefined(my_birthtime) || (my_birthtime + 25000 <= gettime()))
			return;
			
		// grant it to whoever did at least 40 damage and got the most out of the two players.
		if ((level.hunter_damage_p1[my_id] > 40) || (level.hunter_damage_p2[my_id] > 40))
		{
			if (level.hunter_damage_p1[my_id] > level.hunter_damage_p2[my_id])
				thread pulse_kill_counter_hud(point_value, 0);
			else
				thread pulse_kill_counter_hud(0, point_value);
		}
	}
}

dialog_hunter_enemies(enemy_tag, wait_time)
{
	// prevent hunter spawn dialogs from happening too frequently
	if (isdefined(level.hunter_dialog_throttle))
	{
		if (!isdefined(level.hunter_dialog_time))
			level.hunter_dialog_time = gettime() - level.hunter_dialog_throttle - 1;
	
		time_since = gettime() - level.hunter_dialog_time;
		if (time_since <= level.hunter_dialog_throttle)
			return;
	
		level.hunter_dialog_time = gettime();
	}

	if (isdefined(wait_time))
		wait wait_time;

	assertex(isdefined(level.dialog), "dialog_hunter_enemies requires level.dialog to be defined before it can play anything.");

	sound_selection = randomint(level.dialog[enemy_tag].size);
	thread maps\_utility::radio_dialogue(level.dialog[enemy_tag][sound_selection]);
}

dialog_hunter_enemies_setup(enemy_tag, wait_time)
{
	if (!isdefined(level.dialog))
		level.dialog = [];

	//hunter two-one this is overlord actual, we're seeing enemy reinforcements to your north, over.	
	level.dialog["bank_enemies"][0] = "inv_hqr_enemynorth";
	//be advised hunter two-one, you got enemy infantry by that bank to the north, over.	
	level.dialog["bank_enemies"][1] = "inv_hqr_banktonorth";
	//hunter two-one, be advised, enemy foot-mobiles approaching north of your location, over.	
	level.dialog["bank_enemies"][2] = "inv_hqr_footmobiles";

	//hunter two-one, hunter four has a visual on hostiles near the nova gas station, over.	
	level.dialog["gas_station_enemies"][0] = "inv_hqr_novagasstation";
	//hunter two-one, relay from goliath two, enemy reinforcements approaching from the west, over.	
	level.dialog["gas_station_enemies"][1] = "inv_hqr_enemywest";
	//hunter two-one, tangos approaching near the diner to the west, over.	
	level.dialog["gas_station_enemies"][2] = "inv_hqr_dinerwest";

	//hunter two-one, overlord. enemy foot-mobiles approaching you from the southeast, over.	
	level.dialog["taco_enemies"][0] = "inv_hqr_southeast";
	//hunter two-one, goliath one has a visual on hostiles coming from the southeast, over.	
	level.dialog["taco_enemies"][1] = "inv_hqr_visualse";
	//hunter two-one, be advised, enemy foot-mobiles have been sighted near the taco joint, over.	
	level.dialog["taco_enemies"][2] = "inv_hqr_tacojoint";
}

// ---------------------------------------------------------------------------------

hud_create_kill_counter()
{
	level endon("special_op_failed");

	yline = 2;
	thread hud_create_p1_counter_nodraw();
		
	hudelem = so_create_hud_item(yline, so_hud_ypos(), &"SO_KILLSPREE_INVASION_HUD_REMAINING", self);
	hudelem_score = so_create_hud_item(yline, so_hud_ypos(), undefined, self);
	hudelem_score.alignx = "left";
	
	self.kill_counter_hud = hudelem_score;
	
	old_score = level.points_counter_display;
	while (true)
	{
		hudelem_score setvalue(level.points_counter_display);

		if (level.points_counter_display <= 0)
		{
			hudelem thread so_hud_pulse_success();
			hudelem_score thread so_hud_pulse_success();
		}
		else if (level.points_counter_display < old_score)
		{
			if (level.points_counter_display <= 5000)
			{
				hudelem thread so_hud_pulse_close();
				hudelem_score thread so_hud_pulse_close();
			}
			else
			{
			    hudelem thread so_hud_pulse_default();
				hudelem_score thread so_hud_pulse_default();
			}
			old_score = level.points_counter_display;
		}
		
		if (common_scripts\utility::flag("challenge_success"))
		{
			break;
		}

		level waittill("score_updated");
	}

	hudelem_score setvalue(0);

	hudelem thread so_remove_hud_item();
	hudelem_score thread so_remove_hud_item();
}

hud_create_p1_counter()
{
	level endon("special_op_failed");
	
	hudelem = so_create_hud_item(4, so_hud_ypos(), &"SO_KILLSPREE_INVASION_PLAYER_LINE", self);
	hudelem_score = so_create_hud_item(4, so_hud_ypos(), undefined, self);
	hudelem_score.alignx = "left";
	hudelem setplayernamestring(level.player);

	self.kill_msg_hud_p1 = hudelem;
	self.kill_counter_hud_p1 = hudelem_score;

	//thread info_hud_handle_fade(hudelem);
	//thread info_hud_handle_fade(hudelem_score);
	
	while (true)
	{
		level.player.total_score = level.points_p1_display;
		hudelem_score setvalue(level.points_p1_display);
		if (common_scripts\utility::flag("challenge_success"))
			break;

		level waittill("score_updated");
	}

	hudelem_score setvalue(level.points_p1_display);
	level.player.total_score = level.points_p1_display;

	hudelem thread so_remove_hud_item();
	hudelem_score thread so_remove_hud_item();
}

hud_create_p1_counter_nodraw()
{
	level endon("special_op_failed");

	while (true)
	{
		level.player.total_score = level.points_p1_display;
		if (common_scripts\utility::flag("challenge_success"))
			break;

		level waittill("score_updated");
	}

	level.player.total_score = level.points_p1_display;
}

hud_create_p2_counter()
{
	level endon("special_op_failed");

	hudelem = so_create_hud_item(5, so_hud_ypos(), &"SO_KILLSPREE_INVASION_PLAYER_LINE", self);
	hudelem_score = so_create_hud_item(5, so_hud_ypos(), undefined, self);
	hudelem_score.alignx = "left";
	hudelem setplayernamestring(level.player2);

	self.kill_msg_hud_p2 = hudelem;
	self.kill_counter_hud_p2 = hudelem_score;

	//thread info_hud_handle_fade(hudelem);
	//thread info_hud_handle_fade(hudelem_score);

	while (true)
	{
		level.player2.total_score = level.points_p2_display;
		hudelem_score setvalue(level.points_p2_display);
		if (common_scripts\utility::flag("challenge_success"))
			break;

		level waittill("score_updated");
	}

	level.player2.total_score = level.points_p2_display;
	hudelem_score setvalue(level.points_p2_display);

	hudelem thread so_remove_hud_item();
	hudelem_score thread so_remove_hud_item();
}

// ctw - egads this is terrible.
pulse_kill_counter_hud(points_p1, points_p2)
{
	level endon("special_op_terminated");

	if (!isdefined(points_p1))
		points_p1 = 0;
	if (!isdefined(points_p2))
		points_p2 = 0;

	if (points_p1 > 0)
		level.player thread hud_create_kill_splash(points_p1);
	if (points_p2 > 0)
		level.player2 thread hud_create_kill_splash(points_p2);

	points = points_p1 + points_p2;

	level.points_counter -= points;
	level.points_p1 += points_p1;
	level.points_p2 += points_p2;

	// allow pulse requests to queue up, but if we've already got one active, then just add and get out.
	level.pulse_requests[level.pulse_requests.size] = points;
	level.pulse_requests_p1[level.pulse_requests_p1.size] = points_p1;
	level.pulse_requests_p2[level.pulse_requests_p2.size] = points_p2;
	if (level.pulse_requests.size > 1)
		return;

	while ((level.pulse_requests.size > 0) &&  !common_scripts\utility::flag("challenge_success"))
	{
		level.player playsound("arcademode_2x");
		level.points_counter_display -= level.pulse_requests[0];
		
		// don't do the vo except on the big updates.
		if (level.points_counter_display > 5999)
			thread so_dialog_counter_update(level.points_counter_display, level.points_max, level.hunter_kill_value);
		
		level.points_p1_display += level.pulse_requests_p1[0];
		if (level.player.points_combo_unused > 0)
		{
			level.points_counter_display -=	level.player.points_combo_unused;
			level.points_counter -= level.player.points_combo_unused;
			level.points_p1_display += level.player.points_combo_unused;
			level.player.points_combo_unused = 0;
		}
		
		if (level.points_counter_display <= 0)
		{
			level.points_counter = 0;
			level.points_counter_display = 0;
			common_scripts\utility::flag_set("challenge_success");
			level notify("score_updated");
			break;
		}
		
		level notify("score_updated");

		wait 0.5;
		pulse_purge_request();
	}
	
	level notify ("pulse_queue_processed");
}

pulse_purge_request()
{
	for (i = level.pulse_requests.size - 1; i > 0; i--)
	{
		level.pulse_requests[i - 1] = level.pulse_requests[i];
		level.pulse_requests_p1[i - 1] = level.pulse_requests_p1[i];
		level.pulse_requests_p2[i - 1] = level.pulse_requests_p2[i];
	}
	
	level.pulse_requests[level.pulse_requests.size - 1] = undefined;
	level.pulse_requests_p1[level.pulse_requests_p1.size - 1] = undefined;
	level.pulse_requests_p2[level.pulse_requests_p2.size - 1] = undefined;
}

// this is not a good way to do this at all, but is good enough for a quick review.
hud_create_kill_splash(points)
{
	level endon("special_op_terminated");

	self notify("hud_create_kill_splash");
	self endon("hud_create_kill_splash");
	
	if (!isdefined(self.hud_kill_splash_total))
	{
		self.hud_kill_splash_total = points;
		self.hud_kill_splash_max = points;

		self.hud_kill_splash_points = hud_create_kill_splash_default(self);

		self.hud_kill_splash_msg = hud_create_kill_splash_default(self);
		self.hud_kill_splash_msg.y = self.hud_kill_splash_points.y - 10;

	}
	else
	{
		self.hud_kill_splash_total += points;
		if (points > self.hud_kill_splash_max)
			self.hud_kill_splash_max = points;

		if (!isdefined(self.hud_kill_combo_total))
		{
			self.hud_kill_combo_total = 2;
			self.hud_kill_combo = hud_create_kill_splash_default(self, &"SO_KILLSPREE_INVASION_SPLASH_COMBO");
			self.hud_kill_combo.y = self.hud_kill_splash_points.y - 30;
			
			self.hud_kill_combo_points = hud_create_kill_splash_default(self, &"SO_KILLSPREE_INVASION_SPLASH_BONUS");
			self.hud_kill_combo_points.y = self.hud_kill_splash_points.y + 15;
			self.hud_combo_bonus = 0;
		}
		else
		{
			self.hud_kill_combo_total++;
		}

		combo_bonus = level.points_combo_base * self.hud_kill_combo_total;
		self.hud_combo_bonus += combo_bonus;
		self.points_combo_unused += combo_bonus;
	}

	self.hud_kill_splash_points setvalue(self.hud_kill_splash_total);
	self.hud_kill_splash_points.alpha = 1;
	
	self.hud_kill_splash_msg.label = hud_splash_kill_style(points);
	self.hud_kill_splash_msg.alpha = 1;

	if (isdefined(self.hud_kill_combo_total))
	{
		self.hud_kill_combo setvalue(self.hud_kill_combo_total);
		self.hud_kill_combo.alpha = 1;
		self.hud_kill_combo.fontscale = 1.0 + (0.1 * self.hud_kill_combo_total);
		if (self.highest_combo < self.hud_kill_combo_total)
			self.highest_combo = self.hud_kill_combo_total;

		self.hud_kill_combo_points setvalue(self.hud_combo_bonus);  // &so_killspree_invasion_splash_bonus
		self.hud_kill_combo_points.alpha = 1;
	}

	// when reloading, give the player a little bit of extra time.
	timer = level.combo_time_window - 0.25;
	while (timer > 0)
	{
		wait 0.05;
		if (self isreloading())
			timer -= 0.025;
		else
			timer -= 0.05;
	}
	
	self.hud_kill_splash_points fadeovertime(0.25);
	self.hud_kill_splash_points.alpha = 0;

	self.hud_kill_splash_msg fadeovertime(0.25);
	self.hud_kill_splash_msg.alpha = 0;

	if (isdefined(self.hud_kill_combo_total))
	{
		self.hud_kill_combo fadeovertime(0.25);
		self.hud_kill_combo.alpha = 0;

		self.hud_kill_combo_points fadeovertime(0.25);
		self.hud_kill_combo_points.alpha = 0;
	}
		
	wait 0.25;
	
	if (isdefined(self.hud_kill_splash_points))
		self.hud_kill_splash_points destroy();
	if (isdefined(self.hud_kill_splash_msg))
		self.hud_kill_splash_msg destroy();
	self.hud_kill_splash_total = undefined;
	
	if (isdefined(self.hud_kill_combo))
		self.hud_kill_combo destroy();
	if (isdefined(self.hud_kill_combo_points))
		self.hud_kill_combo_points destroy();
	self.hud_kill_combo_total = undefined;
}

hud_splash_destroy()
{
	level waittill("special_op_terminated");
	
	if (isdefined(self.hud_kill_splash_points))
		self.hud_kill_splash_points destroy();
	if (isdefined(self.hud_kill_splash_msg))
		self.hud_kill_splash_msg destroy();
	if (isdefined(self.hud_kill_combo))
		self.hud_kill_combo destroy();
	if (isdefined(self.hud_kill_combo_points))
		self.hud_kill_combo_points destroy();
}

hud_splash_kill_style(points, current_msg)
{
	if (points == level.hunter_finish_value)
	{
		self.solid_kills++;
		return &"SO_KILLSPREE_INVASION_SCORE_FINISHED";
	}

	if (points == level.hunter_kill_value)
	{
		self.solid_kills++;
		return &"SO_KILLSPREE_INVASION_SCORE_KILL";
	}
		
	if (points == level.hunter_brutal_value)
	{
		self.heartless_kills++;
		return &"SO_KILLSPREE_INVASION_SCORE_BRUTAL";
	}
		
	if (points == level.btr_kill_value)
	{
		return &"SO_KILLSPREE_INVASION_SCORE_BTR80";
	}
}

hud_convert_to_points(value)
{
	return value;
/*	thousands = 0;
	if (value >= 1000)
		thousands = int(value / 1000);
	hundreds = value - (thousands * 1000);
	
	label = "";
	if (thousands > 0)
	{
		label += thousands + ",";
		if (hundreds < 100)
			label += "0";
		if (hundreds < 10)
			label += "0";
	}
	label += hundreds;
	
	return label;*/
}

hud_create_kill_splash_default(player, message)
{
	hudelem = newclienthudelem(player);
	hudelem.alignx = "center";
	hudelem.aligny = "middle";
	hudelem.horzalign = "center";
	hudelem.vertalign = "middle";
	hudelem.x = 0;
	hudelem.y = -70;
	hudelem.fontscale = 1.2;
	hudelem.font = "bank";
	hudelem.foreground = 1;
	hudelem.hidewheninmenu = true;
	hudelem.hidewhendead = true;
	hudelem.sort = 2;
	hudelem set_hud_yellow();
	if (isdefined(message))
		hudelem.label = message;
		
	return hudelem;
}

// ---------------------------------------------------------------------------------

door_diner_open()
{
	diner_back_door = getent("diner_back_door", "targetname");
	diner_back_door rotateyaw(85, .3);//counter clockwise
	diner_back_door playsound("diner_backdoor_slams_open");
	diner_back_door connectpaths();
}

door_nates_locker_open()
{
	nates_meat_locker_door = getent("nates_meat_locker_door", "targetname");
	nates_meat_locker_door_model = getent(nates_meat_locker_door.target, "targetname");
	nates_meat_locker_door_model linkto(nates_meat_locker_door);
	nates_meat_locker_door rotateyaw(-82, .1, 0, 0 );
	nates_meat_locker_door connectpaths();
}

door_bt_locker_open()
{
	bt_locker_door = getent("bt_locker_door", "targetname");
	bt_locker_door rotateyaw(-172, .1, 0, 0 );
	bt_locker_door connectpaths();
}

// ---------------------------------------------------------------------------------