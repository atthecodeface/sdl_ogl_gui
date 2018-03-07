(** Copyright (C) 2017,  Gavin J Stark.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file          sdl_ogl.ml
 * @brief         SDL input/output for OpenGl framework library
 *
 *)

open Batteries
open Ogl_gui
open Tsdl
open Tgl4

(*a Types *)
(*t sdl_result - not an ogl_result *)
type 'a sdl_result = 'a Sdl.result

type t_win_handle = Ogl_gui.Types.t_window_handle
type 'a ogl_result = 'a Ogl_gui.Utils.ogl_result

(*f >>= standard monadic function for ogl_result *)
let ( >>= ) (x: 'a ogl_result ) f = match x with Ok v -> f v | Error _ as e -> e

(*f monadic contiunation operator for sdl_result *)
let ( >>>= ) (x: 'a sdl_result) (f: 'a -> 'b ogl_result) : 'b ogl_result =
  match x with
    Ok v -> f v
  |  Error (`Msg e) -> Error e

(*a SDL OpenGL window module - runs an Ogl_app (single window for now) *)
module Sdl_ogl_window = struct
    (*t type of module - SDL window and window's OpenGL context *)
    type t = {
        win : Tsdl.Sdl.window;
        ctx : Tsdl.Sdl.gl_context;
      }

    (*f create *)
    let create ?width:(width=640) ?height:(height=480) ?title:(title="banana") _ : t ogl_result =
      let sdl_atts = Sdl.Window.(opengl + resizable) in
      Sdl.gl_set_attribute Sdl.Gl.context_profile_mask Sdl.Gl.context_profile_core
      >>>= fun () ->
      Sdl.gl_set_attribute Sdl.Gl.doublebuffer 1
      >>>= fun () ->
      Sdl.create_window ~w:width ~h:height title sdl_atts
      >>>= fun win ->
      Sdl.gl_create_context win
      >>>= fun ctx ->
      Sdl.gl_make_current   win ctx
      >>>= fun () ->
      Ok { win ; ctx }

    (*f destroy *)
    let destroy t =
      Sdl.gl_delete_context t.ctx;
      Sdl.destroy_window t.win;
      Pervasives.Ok ()

    (*f reshape *)
    let reshape t w h app wh =
      ignore (Sdl.gl_make_current t.win t.ctx);
      app#reshape wh w h

    (*f Draw *)
    let draw t app wh =
      ignore (Sdl.gl_make_current t.win t.ctx);
      app#draw wh ;
      Sdl.gl_swap_window t.win

   let is_window w t = (t.win = w)
    (*f All done *)
end

(*a SDL OpenGL application - runs an Ogl_app *)
exception SDL_Error of string
let sdl_result_value r = 
  match r with
  | Error (`Msg s) -> raise (SDL_Error s)
  | Ok x -> x

module Sdl_ogl_app = struct
    (*t type of module - SDL window and window's OpenGL context *)
    type t = {
        app : Ogl_gui.Types.t_ogl_app ;
        win_ctxs :  (t_win_handle * Sdl_ogl_window.t) list ref ;
        start_time : Sdl.uint32;
      }

    (*f create_window *)
    let create_window ?width:(width=640) ?height:(height=480) ?title:(title="banana") t wh : t_win_handle ogl_result =
      Sdl_ogl_window.create ~width:width ~height:height ~title:title ()
      >>= fun wc ->
      t.win_ctxs := !(t.win_ctxs) @ [(wh,wc)];
      Ok wh

    (*f add_mappings *)
    let add_mappings _ =
      match Sdl.rw_from_file  "gamecontrollerdb.txt" "r" with
      | Error (`Msg s) -> Printf.printf "Opening mapping file returned '%s'\n" s
      | Ok rw -> (
      match Sdl.game_controller_add_mapping_from_rw rw true with
      | Error (`Msg s) -> Printf.printf "Adding mappings returned '%s'\n" s
      | Ok _ -> ()
      );
      let x = Sdl.game_controller_add_mapping "030000004c0500006802000000010000,PS3 Controller,a:b14,b:b13,back:b0,dpdown:b6,dpleft:b7,dpright:b5,dpup:b4,guide:b16,leftshoulder:b10,leftstick:b1,lefttrigger:b8,leftx:a0,lefty:a1,rightshoulder:b11,rightstick:b2,righttrigger:b9,rightx:a2,righty:a3,start:b3,x:b15,y:b12,platform:Mac OS X," in
      let x = sdl_result_value x in
      Printf.printf "Adding mapping got %b\n" x;
      Printf.printf "Num joysticks %d\n" (sdl_result_value (Sdl.num_joysticks ()));
      match Sdl.game_controller_open 0 with
      | Ok gc -> Printf.printf "Found game controller %s\n" (sdl_result_value (Sdl.game_controller_name gc))
      | _ -> ()

    (*f init *)
    let init app : t ogl_result =
      Sdl.init Sdl.Init.(video + timer + joystick)
     >>>= fun () ->
      add_mappings ();
      let t = {app ; win_ctxs = ref []; start_time=Sdl.get_ticks ()} in
      let cwin ~width ~height ~title = create_window ~width:width ~height:height ~title:title t in
      app#set_create_window cwin ;
      Ok t

    (*f destroy *)
    let destroy t : 'a ogl_result =
      let d wh_wc = let (_,wc) = wh_wc in (ignore (Sdl_ogl_window.destroy wc)) in
      List.iter d !(t.win_ctxs);
      Sdl.quit ();
      Ok ()

    (*f wh_wc_of_wh *)
    let wh_wc_of_wh t win_wh = 
      let find_wh acc wh_wc =
        let (wh,wc) = wh_wc in
        if (wh=win_wh) then Some wh_wc else acc
      in
      List.fold_left find_wh None !(t.win_ctxs)

    (*f wh_wc_of_win *)
    let wh_wc_of_win t opt_win = 
      match opt_win with 
        None -> None 
      | Some win ->
         let find_win acc wh_wc =
           let (wh,wc) = wh_wc in
           if (Sdl_ogl_window.is_window win wc) then Some wh_wc else acc
         in
         List.fold_left find_win None !(t.win_ctxs)

    (*f wh_of_wid *)
    let wh_of_wid t wid = 
      match (Sdl.get_window_from_id wid) with
        Ok win -> 
         let find_win acc wh_wc =
           let (wh,wc) = wh_wc in
           if (Sdl_ogl_window.is_window win wc) then Some wh else acc
         in
         List.fold_left find_win None !(t.win_ctxs)
      | _ -> None

    (*f wh_of_win *)
    let wh_of_win t opt_win = 
      match opt_win with 
        None -> None 
      | Some win ->
         let find_win acc wh_wc =
           let (wh,wc) = wh_wc in
           if (Sdl_ogl_window.is_window win wc) then Some wh else acc
         in
         List.fold_left find_win None !(t.win_ctxs)

    (*f get_mouse_wxyb *)
    let get_mouse_wxyb t () = 
      let w = wh_of_win t (Sdl.get_mouse_focus ()) in
      let (b, (x,y)) = Sdl.get_mouse_state () in
      (w,x,y,b)

      let key_scancode e = Sdl.Scancode.enum Sdl.Event.(get e keyboard_scancode)

      (*let get_key_modifiers _ = map_key_modifiers (Sdl.get_mod_state ()) *)
      let get_key_modifiers km = 
        let v f b = (if ((km land f)!=0) then b else 0) in
        ((v Sdl.Kmod.shift 1) lor
         (v Sdl.Kmod.ctrl  2) lor
         (v Sdl.Kmod.alt   4))

      let key_event t e =
        let w = wh_of_win t (Sdl.get_keyboard_focus ()) in
        (w, Sdl.Event.(get e keyboard_keycode), Sdl.Event.(get e keyboard_keymod))

      let handle_key t action e =
        let (w, k, m) = key_event t e in
        let (_, x,y,b) = get_mouse_wxyb t () in
        t.app#key w action k m x y

      let int_of_int32 x = (Int32.to_int x)
      let handle_mouse t action wid which x y options =
        let w = wh_of_wid t wid in
        t.app#mouse w action (int_of_int32 which) x y options

    let handle_joystick t action which axis value options =
        t.app#joystick action (int_of_int32 which) axis value options

      let reshape t win w h =
        match wh_wc_of_win t win with 
          Some wh_wc -> let (wh,wc)=wh_wc in Sdl_ogl_window.reshape wc w h (t.app) wh
        | None -> ()

      let draw t win =
        match wh_wc_of_win t win with 
          Some wh_wc -> let (wh,wc)=wh_wc in Sdl_ogl_window.draw wc (t.app) wh
        | None -> ()

      let redraw t wh =
        match wh_wc_of_wh t wh with 
          Some wh_wc -> let (wh,wc)=wh_wc in Sdl_ogl_window.draw wc (t.app) wh
        | None -> ()

      let handle_window_event t e =
        let wid            = Sdl.Event.(get e window_window_id) in
        match (Sdl.get_window_from_id wid) with
          Error _ -> ()
        | Ok win ->
           let window_event   = Sdl.Event.(window_event_enum (get e window_event_id)) in
           begin match window_event with
           | `Exposed  | `Resized ->
              let w, h = Sdl.get_window_size win in
              reshape t (Some win) w h;
              draw t (Some win)
           | _ -> ()
           end

    (*f Show event *)
    let show_event e =
      match Sdl.Event.(enum (get e typ)) with
      | `App_did_enter_background -> (
        Printf.printf "App_did_enter_background\n";
      )     
      | `App_did_enter_foreground -> (
        Printf.printf "App_did_enter_foreground\n";
      )    
      | `App_low_memory -> (
        Printf.printf "App_low_memory\n";
      )     
      | `App_terminating -> (
        Printf.printf "App_terminating\n";
      )     
      | `App_will_enter_background -> (
        Printf.printf "App_will_enter_background\n";
      )    
      | `App_will_enter_foreground -> (
        Printf.printf "App_will_enter_foreground\n";
      )     
      | `Clipboard_update -> (
        Printf.printf "Clipboard_update\n";
      )    
      | `Controller_axis_motion -> (
        Printf.printf "Controller_axis_motion\n";
      )     
      | `Controller_button_down -> (
        Printf.printf "Controller_button_down\n";
      )    
      | `Controller_button_up -> (
        Printf.printf "Controller_button_up\n";
      )     
      | `Controller_device_added -> (
        Printf.printf "Controller_device_added\n";
      )    
                  
      | `Controller_device_remapped -> (
        Printf.printf "Controller_device_remapped\n";
      )     
      | `Controller_device_removed -> (
        Printf.printf "Controller_device_removed\n";
      )    
      | `Dollar_gesture -> (
        Printf.printf "Dollar_gesture\n";
      )     
      | `Dollar_record -> (
        Printf.printf "Dollar_record\n";
      )     
      | `Drop_file -> (
        Printf.printf "Drop_file\n";
      )     
      | `Finger_down -> (
        Printf.printf "Finger_down\n";
      )    
      | `Finger_motion -> (
        Printf.printf "Finger_motion\n";
      )     
      | `Finger_up -> (
        Printf.printf "Finger_up\n";
      )     
      | `Joy_axis_motion -> (
        let (w,a,v) = Sdl.Event.(get e joy_axis_which, get e joy_axis_axis, get e joy_axis_value) in
        Printf.printf "Joy_axis_motion %ld %d %d \n" w a v;
      )     
      | `Joy_ball_motion -> (
        Printf.printf "Joy_ball_motion\n";
      )    
      | `Joy_button_down -> (
        Printf.printf "Joy_button_down\n";
      )     
      | `Joy_button_up -> (
        Printf.printf "Joy_button_up\n";
      )     
      | `Joy_device_added -> (
        Printf.printf "Joy_device_added\n";
      )    
      | `Joy_device_removed -> (
        Printf.printf "Joy_device_removed\n";
      )     
      | `Joy_hat_motion -> (
        Printf.printf "Joy_hat_motion\n";
      )     
      | `Key_down -> (
        Printf.printf "Key_down\n";
      )     
      | `Key_up -> (
        Printf.printf "Key_up\n";
      )    
      | `Mouse_button_down -> (
        Printf.printf "Mouse_button_down\n";
      )     
      | `Mouse_button_up -> (
        Printf.printf "Mouse_button_up\n";
      )     
      | `Mouse_motion -> (
        Printf.printf "Mouse_motion\n";
      )    
      | `Mouse_wheel -> (
        Printf.printf "Mouse_wheel\n";
      )     
      | `Multi_gesture -> (
        Printf.printf "Multi_gesture\n";
      )     
      | `Quit -> (
        Printf.printf "Quit\n";
      )     
      | `Sys_wm_event -> (
        Printf.printf "Sys_wm_event\n";
      )    
      | `Text_editing -> (
        Printf.printf "Text_editing\n";
      )     
      | `Text_input -> (
        Printf.printf "Text_input\n";
      )     
      | `Unknown x -> (
        Printf.printf "Unknown %d\n" x;
      )
      | `User_event -> (
        Printf.printf "User_event\n";
      )    
                         
      | `Window_event -> (
        Printf.printf "Window_event\n";
      )
      ;
      ()
    
    (*f Event loop *)
    let event_loop t : 'a ogl_result =
      let e = Sdl.Event.create () in
      let rec loop delay =
        if Option.is_some delay then
        begin
          let redraw_wh = (t.app)#need_redraw in
          List.iter (redraw t) redraw_wh;
          Sdl.delay (Int32.of_int (Option.get delay))
        end;
        let has_event = Sdl.poll_event (Some e) in
        if has_event then begin
            (*show_event e;*)
            let event_type e = Sdl.Event.(enum (get e typ)) in
            match event_type e with
            | `Quit -> Pervasives.Ok ()
            | `Key_down ->
               handle_key t Ogl_gui.Types.Key_action_press e;
               loop None
            | `Key_up   ->
               handle_key t Ogl_gui.Types.Key_action_release e;
               loop None
            | `Mouse_button_down ->
               Sdl.Event.(handle_mouse t (Ogl_gui.Types.Mouse_action_down)
                                         (get e mouse_button_window_id)
                                         (get e mouse_button_which)
                                         (get e mouse_button_x)
                                         (get e mouse_button_y)
                                         [|(get e mouse_button_button); (get e mouse_button_clicks)|]);
               loop None
            | `Mouse_button_up ->
               Sdl.Event.(handle_mouse t (Ogl_gui.Types.Mouse_action_up)
                                         (get e mouse_button_window_id)
                                         (get e mouse_button_which)
                                         (get e mouse_button_x)
                                         (get e mouse_button_y)
                                         [|(get e mouse_button_button); (get e mouse_button_clicks)|]);
               loop None
            | `Mouse_motion ->
               Sdl.Event.(handle_mouse t (Ogl_gui.Types.Mouse_action_motion)
                                         (get e mouse_motion_window_id)
                                         (get e mouse_motion_which)
                                         (get e mouse_motion_x)
                                         (get e mouse_motion_y)
                                         [|int_of_int32(get e mouse_motion_state); (get e mouse_motion_xrel); (get e mouse_motion_yrel)|]);
               loop None
            | `Mouse_wheel ->
               Sdl.Event.(handle_mouse t (Ogl_gui.Types.Mouse_action_wheel)
                                         (get e mouse_wheel_window_id)
                                         (get e mouse_wheel_which)
                                         (get e mouse_wheel_x)
                                         (get e mouse_wheel_y)
                                         [| |]);
               loop None
            | `Joy_axis_motion ->
               Sdl.Event.(handle_joystick t (Ogl_gui.Types.Joystick_action_axis)
                                         (get e joy_axis_which)
                                         (get e joy_axis_axis)
                                         (get e joy_axis_value)
                                         [| |]);
               loop None
            | `Window_event ->
               handle_window_event t e;
               loop None
            | _ -> loop None
          end
        else
          begin
            (*draw t app;*)
            match (t.app)#idle with
              None -> Pervasives.Ok ()
            | Some delay ->
               loop (Some delay)
          end
      in
      (*draw t app; *)
      loop None

    (*f All done *)
end

(*a Toplevel *)
(*f run_app *)
let run_app ?width:(width=640) ?height:(height=400) ?title:(title="Untitled") ?ogl_root_dir:(ogl_root_dir="") (app:Ogl_gui.App.ogl_app) =
  Sdl_ogl_app.init app
  >>= fun sdl_app ->
  (app#create ogl_root_dir)
  >>= fun () ->
  Sdl_ogl_app.event_loop sdl_app
  >>= fun () ->
  (app#destroy)
  >>= fun () ->
  Sdl_ogl_app.destroy sdl_app
  >>= fun () ->
  Ok ()
